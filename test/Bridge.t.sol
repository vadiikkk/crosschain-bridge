// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Erc20Token.sol";
import "../src/Bridge.sol";

contract BridgeTest is Test {
    Erc20Token token;
    Bridge bridgeA;
    Bridge bridgeB;

    address user = address(0xCAFE);
    address relayer = address(0xBEEF);
    address attacker = address(0xDEAD);

    event Deposit(address indexed from, address indexed to, uint256 amount, bytes32 depositId, uint256 toChainId);
    event Redeem(address indexed to, uint256 amount, bytes32 depositId);

    function setUp() public {
        token = new Erc20Token("ERC20 Token", "ERCT");

        bridgeA = new Bridge(address(token));
        bridgeB = new Bridge(address(token));

        token.grantRole(token.BURN_ROLE(), address(bridgeA));
        token.grantRole(token.MINT_ROLE(), address(bridgeB));

        bridgeB.grantRole(bridgeB.RELAYER_ROLE(), relayer);

        token.grantRole(token.MINT_ROLE(), address(this));
        token.mint(user, 100 ether);
    }

    function test_DepositAndRedeem_HappyPath() public {
        vm.startPrank(user);
        vm.expectEmit(true, true, false, false);
        emit Deposit(user, user, 0, bytes32(0), 0);
        bytes32 depositId = bridgeA.deposit(user, 50 ether, 2);
        vm.stopPrank();

        assertEq(token.balanceOf(user), 50 ether);
        assertEq(token.totalSupply(), 50 ether);

        vm.prank(relayer);
        vm.expectEmit(true, false, false, true);
        emit Redeem(user, 50 ether, depositId);
        bridgeB.redeem(user, 50 ether, depositId);

        assertEq(token.balanceOf(user), 100 ether);
        assertEq(token.totalSupply(), 100 ether);
        assertTrue(bridgeB.processedDeposits(depositId));
    }

    function test_Redeem_RevertOnDoubleProcessing() public {
        vm.startPrank(user);
        bytes32 depositId = bridgeA.deposit(user, 10 ether, 2);
        vm.stopPrank();

        vm.prank(relayer);
        bridgeB.redeem(user, 10 ether, depositId);

        vm.prank(relayer);
        vm.expectRevert(bytes("Bridge: already processed"));
        bridgeB.redeem(user, 10 ether, depositId);
    }

    function test_Redeem_RevertIfNotRelayer() public {
        vm.startPrank(user);
        bytes32 depositId = bridgeA.deposit(user, 5 ether, 2);
        vm.stopPrank();

        vm.prank(attacker);
        vm.expectRevert();
        bridgeB.redeem(user, 5 ether, depositId);
    }

    function test_Deposit_RevertOnZeroTo() public {
        vm.prank(user);
        vm.expectRevert(bytes("Bridge: Zero to"));
        bridgeA.deposit(address(0), 1 ether, 2);
    }

    function test_Deposit_RevertOnZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(bytes("Bridge: Zero amount"));
        bridgeA.deposit(user, 0, 2);
    }

    function test_Deposit_RevertOnSameChain() public {
        vm.prank(user);
        vm.expectRevert(bytes("Bridge: Same chain"));
        bridgeA.deposit(user, 1 ether, block.chainid);
    }

    function test_Redeem_RevertOnZeroTo() public {
        vm.startPrank(user);
        bytes32 depositId = bridgeA.deposit(user, 1 ether, 2);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert(bytes("Bridge: Zero to"));
        bridgeB.redeem(address(0), 1 ether, depositId);
    }

    function test_Redeem_RevertOnZeroAmount() public {
        vm.startPrank(user);
        bytes32 depositId = bridgeA.deposit(user, 1 ether, 2);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert(bytes("Bridge: Zero amount"));
        bridgeB.redeem(user, 0, depositId);
    }

    function test_Deposit_EmitsEventTopics() public {
        vm.prank(user);
        vm.expectEmit(true, true, false, false);
        emit Deposit(user, user, 0, bytes32(0), 0);
        bridgeA.deposit(user, 3 ether, 12345);
    }
}
