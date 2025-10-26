import 'dotenv/config';
import { Contract, JsonRpcProvider, Wallet, type EventLog, type Log } from 'ethers';
import pino from 'pino';

const log = pino({
  level: 'info',
  transport: { target: 'pino-pretty', options: { colorize: true } }
});

const {
  SRC_RPC_URL,
  SRC_BRIDGE_ADDRESS,
  DST_RPC_URL,
  DST_BRIDGE_ADDRESS,
  RELAYER_PRIVATE_KEY,
  REQUIRED_CONFIRMATIONS,
  MAX_RETRIES,
} = process.env;

if (!SRC_RPC_URL || !DST_RPC_URL || !SRC_BRIDGE_ADDRESS || !DST_BRIDGE_ADDRESS || !RELAYER_PRIVATE_KEY) {
  log.error('Missing required env vars. Check .env');
  process.exit(1);
}

const requiredConfs = Number(REQUIRED_CONFIRMATIONS ?? 2);
const maxRetries = Number(MAX_RETRIES ?? 5);

const BRIDGE_ABI = [
  'event Deposit(address indexed from, address indexed to, uint256 amount, bytes32 depositId, uint256 toChainId)',
  'event Redeem(address indexed to, uint256 amount, bytes32 depositId)',
  'function redeem(address to, uint256 amount, bytes32 depositId) external',
];

const srcProvider = new JsonRpcProvider(SRC_RPC_URL, { name: 'anvilA', chainId: 1337 });
const dstProvider = new JsonRpcProvider(DST_RPC_URL, { name: 'anvilB', chainId: 2337 });
const relayer = new Wallet(RELAYER_PRIVATE_KEY, dstProvider);

const srcBridge = new Contract(SRC_BRIDGE_ADDRESS!, BRIDGE_ABI, srcProvider);
const dstBridge = new Contract(DST_BRIDGE_ADDRESS!, BRIDGE_ABI, relayer);

async function getChainIds() {
  const [srcNet, dstNet] = await Promise.all([srcProvider.getNetwork(), dstProvider.getNetwork()]);
  return { srcId: Number(srcNet.chainId), dstId: Number(dstNet.chainId) };
}

type EventMeta = {
  blockNumber: number;
  transactionHash: string;
};

function extractMeta(ev: EventLog | Log): EventMeta {
  const bn = (ev as any).blockNumber ?? (ev as any).log?.blockNumber;
  const tx = (ev as any).transactionHash ?? (ev as any).log?.transactionHash;
  if (bn == null || tx == null) {
    throw new Error('Cannot extract event metadata (blockNumber/transactionHash)');
  }
  return { blockNumber: Number(bn), transactionHash: String(tx) };
}

type DepositEvent = {
  from: string;
  to: string;
  amount: bigint;
  depositId: string;
  toChainId: bigint;
  meta: EventMeta;
};

async function handleDeposit(evt: DepositEvent, actualDstChainId: number) {
  const { from, to, amount, depositId, toChainId, meta } = evt;
  log.info(
    {
      from, to,
      amount: amount.toString(),
      depositId,
      toChainId: toChainId.toString(),
      txHash: meta.transactionHash,
      srcBlock: meta.blockNumber
    },
    'Deposit detected'
  );

  if (BigInt(actualDstChainId) !== toChainId) {
    log.warn({ expected: actualDstChainId, got: toChainId.toString() }, 'Deposit for different chainId, skipping');
    return;
  }

  await waitConfirmations(meta.blockNumber, requiredConfs);
  log.info({ confs: requiredConfs, srcBlock: meta.blockNumber }, 'Confirmations OK');

  await redeemWithRetry(to, amount, depositId);
}

async function waitConfirmations(blockNumber: number, required: number) {
  while (true) {
    const cur = await srcProvider.getBlockNumber();
    if (cur - blockNumber + 1 >= required) return;
    await new Promise(r => setTimeout(r, 1500));
  }
}

async function redeemWithRetry(to: string, amount: bigint, depositId: string) {
  let attempt = 0;
  let lastError: unknown;
  while (attempt < maxRetries) {
    try {
      const gasEstimate = await dstBridge.redeem.estimateGas(to, amount, depositId);
      const gasLimit = (gasEstimate * 112n) / 100n; // +12%
      const tx = await dstBridge.redeem(to, amount, depositId, { gasLimit });
      log.info({ txHash: tx.hash, to, amount: amount.toString(), depositId }, 'Sent redeem tx');
      const rcpt = await tx.wait();
      log.info({ txHash: rcpt?.hash, status: rcpt?.status }, 'Redeem mined');
      return rcpt;
    } catch (e) {
      lastError = e;
      attempt++;
      const backoffMs = Math.min(1000 * 2 ** attempt, 15000);
      log.warn({ attempt, backoffMs, error: (e as Error)?.message }, 'Redeem failed, retrying');
      await new Promise(r => setTimeout(r, backoffMs));
    }
  }
  throw lastError;
}

async function main() {
  const { srcId, dstId } = await getChainIds();
  log.info({ srcId, dstId, srcBridge: SRC_BRIDGE_ADDRESS, dstBridge: DST_BRIDGE_ADDRESS }, 'Relayer starting');

  srcBridge.on(
    "Deposit",
    async (from: string, to: string, amount: bigint, depositId: string, toChainId: bigint, ev) => {
      const meta = extractMeta(ev as EventLog | Log);

      const dep: DepositEvent = {
        from,
        to,
        amount: BigInt(amount),
        depositId,
        toChainId: BigInt(toChainId),
        meta
      };

      try {
        await handleDeposit(dep, dstId);
      } catch (e) {
        log.error({ error: (e as Error).message, depositId }, 'Live processing failed');
      }
    }
  );

  const shutdown = async (sig: string) => {
    log.info({ sig }, 'Shutting down...');
    srcBridge.removeAllListeners();
    srcProvider.removeAllListeners();
    setTimeout(() => process.exit(0), 300);
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((e) => {
  log.error({ error: (e as Error).message }, 'Fatal error');
  process.exit(1);
});
