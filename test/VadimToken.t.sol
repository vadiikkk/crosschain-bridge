// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VadimToken} from "../src/VadimToken.sol";

contract VadimTokenTest is Test {
    VadimToken token;
    address bridge = address(0xBEEF);
    address user = address(0xCAFE);

    function setUp() public {
        token = new VadimToken("Vadim Token", "VAD");
        token.grantRole(token.MINT_ROLE(), bridge);
        token.grantRole(token.BURN_ROLE(), bridge);
    }

    function test_MintAndBurn() public {
        vm.prank(bridge);
        token.mint(user, 100 ether);
        assertEq(token.balanceOf(user), 100 ether);

        vm.prank(bridge);
        token.burn(user, 40 ether);
        assertEq(token.balanceOf(user), 60 ether);
    }

    function test_RevertIfMintWithoutRole() public {
        vm.expectRevert();
        token.mint(user, 10 ether);
    }
}
