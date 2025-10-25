// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/VadimToken.sol";
import "../src/Bridge.sol";

contract BridgeTest is Test {
    VadimToken token;
    Bridge bridgeA;
    Bridge bridgeB;
    address user = address(0xCAFE);
    address relayer = address(0xBEEF);

    function setUp() public {
        token = new VadimToken("Vadim Token", "VDM");

        bridgeA = new Bridge(address(token));
        bridgeB = new Bridge(address(token));

        token.grantRole(token.BURN_ROLE(), address(bridgeA));
        token.grantRole(token.MINT_ROLE(), address(bridgeB));
        bridgeB.grantRole(bridgeB.RELAYER_ROLE(), relayer);

        token.grantRole(token.MINT_ROLE(), address(this));
        token.mint(user, 100 ether);
    }

    function test_DepositAndRedeem() public {
        vm.startPrank(user);
        token.approve(address(bridgeA), 100 ether);
        bytes32 depositId = bridgeA.deposit(user, 50 ether, 2);
        vm.stopPrank();

        vm.prank(relayer);
        bridgeB.redeem(user, 50 ether, depositId);

        assertEq(token.balanceOf(user), 100 ether);
        assertTrue(bridgeB.processedDeposits(depositId));
    }
}
