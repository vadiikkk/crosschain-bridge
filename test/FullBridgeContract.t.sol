// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Erc20Token.sol";
import "../src/Bridge.sol";

contract FullBridgeContractTest is Test {
    Erc20Token tokenA;
    Bridge bridgeA;

    Erc20Token tokenB;
    Bridge bridgeB;

    address user = address(0xCAFE);
    address relayer = address(0xBEEF);
    address attacker = address(0xDEAD);

    event Deposit(address indexed from, address indexed to, uint256 amount, bytes32 depositId, uint256 toChainId);
    event Redeem(address indexed to, uint256 amount, bytes32 depositId);

    function setUp() public {
        tokenA = new Erc20Token("ERC20 Token A", "ERCTA");
        tokenB = new Erc20Token("ERC20 Token B", "ERCTB");

        bridgeA = new Bridge(address(tokenA));
        bridgeB = new Bridge(address(tokenB));

        tokenA.grantRole(tokenA.BURN_ROLE(), address(bridgeA));
        tokenB.grantRole(tokenB.MINT_ROLE(), address(bridgeB));
        bridgeB.grantRole(bridgeB.RELAYER_ROLE(), relayer);

        tokenA.grantRole(tokenA.MINT_ROLE(), address(this));
        tokenA.mint(user, 100 ether);
    }

    function test_DepositEvent_And_Redeem_Mints_On_Destination() public {
        uint256 amount = 50 ether;
        uint256 dstChainIdMock = 2;

        vm.startPrank(user);

        vm.expectEmit(true, true, false, false);
        emit Deposit(user, user, amount, bytes32(0), dstChainIdMock);

        vm.recordLogs();
        bytes32 returnedDepositId = bridgeA.deposit(user, amount, dstChainIdMock);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(user), 100 ether - amount);
        assertEq(tokenA.totalSupply(), 100 ether - amount);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 depositSig = keccak256("Deposit(address,address,uint256,bytes32,uint256)");
        bool found;
        bytes32 loggedDepositId;
        uint256 loggedAmount;
        uint256 loggedToChainId;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == depositSig) {
                (loggedAmount, loggedDepositId, loggedToChainId) =
                    abi.decode(entries[i].data, (uint256, bytes32, uint256));
                found = true;
                break;
            }
        }

        assertTrue(found, "Deposit event not found");
        assertEq(loggedAmount, amount, "amount mismatch in event");
        assertEq(loggedToChainId, dstChainIdMock, "toChainId mismatch in event");
        assertEq(loggedDepositId, returnedDepositId, "depositId mismatch event vs return");

        vm.prank(relayer);
        vm.expectEmit(true, false, false, true);
        emit Redeem(user, amount, returnedDepositId);
        bridgeB.redeem(user, amount, returnedDepositId);

        assertEq(tokenB.balanceOf(user), amount);
        assertEq(tokenB.totalSupply(), amount);

        assertTrue(bridgeB.processedDeposits(returnedDepositId));
        vm.prank(relayer);
        vm.expectRevert(bytes("Bridge: already processed"));
        bridgeB.redeem(user, amount, returnedDepositId);
    }

    function test_Redeem_OnlyRelayer() public {
        vm.startPrank(user);
        bytes32 id = bridgeA.deposit(user, 1 ether, 2);
        vm.stopPrank();

        vm.prank(attacker);
        vm.expectRevert();
        bridgeB.redeem(user, 1 ether, id);
    }

    function test_Deposit_Reverts() public {
        vm.prank(user);
        vm.expectRevert(bytes("Bridge: Zero to"));
        bridgeA.deposit(address(0), 1 ether, 2);

        vm.prank(user);
        vm.expectRevert(bytes("Bridge: Zero amount"));
        bridgeA.deposit(user, 0, 2);

        vm.prank(user);
        vm.expectRevert(bytes("Bridge: Same chain"));
        bridgeA.deposit(user, 1 ether, block.chainid);
    }

    function test_Redeem_Reverts() public {
        vm.startPrank(user);
        bytes32 id = bridgeA.deposit(user, 1 ether, 2);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert(bytes("Bridge: Zero to"));
        bridgeB.redeem(address(0), 1 ether, id);

        vm.prank(relayer);
        vm.expectRevert(bytes("Bridge: Zero amount"));
        bridgeB.redeem(user, 0, id);
    }
}
