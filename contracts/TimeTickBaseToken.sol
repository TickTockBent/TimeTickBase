// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract TimeTickBaseToken is ERC20, ReentrancyGuard, Ownable(msg.sender), Pausable {

    // This contract will be the token minting contract
    // That is the only thing it will do
    // It will mint tokens based on the time that has passed
    // - TTB

    // This is the time that the contract was created
    uint256 public immutable genesisTime;
    // This is set each time tokens are minted
    uint256 public lastMintTime;
    // This is the precision used for calculations - 1e18
    uint256 private constant PRECISION = 1e18;
    // Admin control bool for minting - used only in emergencies
    bool public mintingEnabled;

    // Admin controls to pause/unpause the contract
    function pause() external onlyOwner {
        _pause();
    }
    function unpause() external onlyOwner {
        _unpause();
    }

    // Public function to allow anyone to call minting
    function mintTokens() external nonReentrant whenNotPaused {
        require(mintingEnabled, "Minting not enabled");
        _processMintAndValidation(0);
    }

    function _processMintAndValidation(int256 correctionFactor) internal {
        require(block.timestamp > lastMintTime, "Already processed");
        
        // First process any expired stakes
        _processExpiredStakes();
        
        // Calculate tokens to mint
        uint256 elapsedTime = block.timestamp - lastMintTime;
        uint256 tokensToMint = elapsedTime * 1 ether; // 1 token per second
        
        // Apply correction if any  
        if (correctionFactor > 0) {
            tokensToMint += uint256(correctionFactor);
        } else if (correctionFactor < 0) {
            tokensToMint -= uint256(-correctionFactor);
        }
        
        // Mint new tokens to this contract
        _mint(address(this), tokensToMint);
        
        lastMintTime = block.timestamp;
    }
}