// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Erc20Token} from "../src/Erc20Token.sol";

contract Erc20TokenTest is Test {
    Erc20Token token;
    address bridge = address(0xBEEF);
    address user = address(0xCAFE);

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    function setUp() public {
        token = new Erc20Token("ERC20 Token", "ERCT");
        token.grantRole(token.MINT_ROLE(), bridge);
        token.grantRole(token.BURN_ROLE(), bridge);
    }

    function test_MintAndBurn() public {
        vm.startPrank(bridge);
        token.mint(user, 100 ether);
        assertEq(token.balanceOf(user), 100 ether);
        assertEq(token.totalSupply(), 100 ether);

        token.burn(user, 40 ether);
        assertEq(token.balanceOf(user), 60 ether);
        assertEq(token.totalSupply(), 60 ether);
        vm.stopPrank();
    }

    function test_RevertIfMintWithoutRole() public {
        vm.expectRevert();
        token.mint(user, 10 ether);
    }

    function test_RevertIfBurnWithoutRole() public {
        vm.expectRevert();
        token.burn(user, 10 ether);
    }

    function test_RevertIfMintToZero() public {
        vm.prank(bridge);
        vm.expectRevert(bytes("ERC20: Zero address"));
        token.mint(address(0), 1 ether);
    }

    function test_RevertIfBurnFromZero() public {
        vm.prank(bridge);
        vm.expectRevert(bytes("ERC20: Zero address"));
        token.burn(address(0), 1 ether);
    }

    function test_RevertIfMintZeroAmount() public {
        vm.prank(bridge);
        vm.expectRevert(bytes("ERC20: Zero amount"));
        token.mint(user, 0);
    }

    function test_RevertIfBurnZeroAmount() public {
        vm.prank(bridge);
        vm.expectRevert(bytes("ERC20: Zero amount"));
        token.burn(user, 0);
    }

    function test_RevertIfBurnExceedsBalance() public {
        vm.startPrank(bridge);
        token.mint(user, 10 ether);
        vm.expectRevert(bytes("ERC20: Burn outnumbers balance"));
        token.burn(user, 20 ether);
        vm.stopPrank();
    }

    function test_EmitEventsOnMintAndBurn() public {
        vm.startPrank(bridge);
        vm.expectEmit(true, false, false, true);
        emit Mint(user, 5 ether);
        token.mint(user, 5 ether);

        vm.expectEmit(true, false, false, true);
        emit Burn(user, 3 ether);
        token.burn(user, 3 ether);
        vm.stopPrank();
    }
}
