// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ITTB is IERC20 {}

contract TTBWrapper1000 is ERC20, ReentrancyGuard {
    ITTB public immutable TTB;
    uint256 public immutable wrapRatio; // How many wrapped tokens per 1 TTB
    bool public immutable allowUnwrap;

    event Wrapped(address indexed user, uint256 ttbAmount, uint256 wrappedAmount);
    event Unwrapped(address indexed user, uint256 wrappedAmount, uint256 ttbAmount);

    constructor(
        address ttbAddress,
        string memory name,
        string memory symbol,
        uint256 _wrapRatio,
        bool _allowUnwrap
    ) ERC20(name, symbol) {
        TTB = ITTB(ttbAddress);
        wrapRatio = _wrapRatio;
        allowUnwrap = _allowUnwrap;
    }

    function wrap(uint256 ttbAmount) external nonReentrant {
        require(ttbAmount > 0, "Amount must be > 0");
        
        uint256 wrappedAmount = ttbAmount * wrapRatio;
        
        // Transfer TTB from user to this contract
        require(TTB.transferFrom(msg.sender, address(this), ttbAmount), "TTB transfer failed");
        
        // Mint wrapped tokens to user
        _mint(msg.sender, wrappedAmount);
        
        emit Wrapped(msg.sender, ttbAmount, wrappedAmount);
    }

    function unwrap(uint256 wrappedAmount) external nonReentrant {
        require(allowUnwrap, "Unwrapping not allowed");
        require(wrappedAmount > 0, "Amount must be > 0");
        
        uint256 ttbAmount = wrappedAmount / wrapRatio;
        require(ttbAmount > 0, "TTB amount too small");
        
        // Burn wrapped tokens
        _burn(msg.sender, wrappedAmount);
        
        // Return TTB to user
        require(TTB.transfer(msg.sender, ttbAmount), "TTB transfer failed");
        
        emit Unwrapped(msg.sender, wrappedAmount, ttbAmount);
    }
}