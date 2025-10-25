// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./Erc20Token.sol";

contract Bridge is AccessControl {
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    Erc20Token public immutable token;

    mapping(bytes32 => bool) public processedDeposits;

    event Deposit(address indexed from, address indexed to, uint256 amount, bytes32 depositId, uint256 toChainId);
    event Redeem(address indexed to, uint256 amount, bytes32 depositId);

    constructor(address tokenAddress) {
        require(tokenAddress != address(0), "Bridge: Zero token");
        token = Erc20Token(tokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function deposit(address to, uint256 amount, uint256 toChainId) external returns (bytes32) {
        require(to != address(0), "Bridge: Zero to");
        require(amount > 0, "Bridge: Zero amount");
        require(toChainId != block.chainid, "Bridge: Same chain");
        bytes32 depositId = keccak256(abi.encodePacked(msg.sender, to, amount, toChainId, block.timestamp));
        token.burn(msg.sender, amount);
        emit Deposit(msg.sender, to, amount, depositId, toChainId);
        return depositId;
    }

    function redeem(address to, uint256 amount, bytes32 depositId) external onlyRole(RELAYER_ROLE) {
        require(to != address(0), "Bridge: Zero to");
        require(amount > 0, "Bridge: Zero amount");
        require(!processedDeposits[depositId], "Bridge: already processed");
        processedDeposits[depositId] = true;
        token.mint(to, amount);
        emit Redeem(to, amount, depositId);
    }
}
