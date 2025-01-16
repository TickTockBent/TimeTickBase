// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract TimeTickBaseToken is ERC20, ReentrancyGuard, Ownable, Pausable {
    // Immutable time tracking
    uint256 public immutable genesisTime;
    uint256 public lastMintTime;
    uint256 public constant MINIMUM_MINT_SECONDS = 15;

    // Reference to the TimeTickBaseDepot contract
    ITimeTickBaseDepot public depot;
    
    // Admin control for emergency pause only
    bool public mintingEnabled;
    
    // Events
    event TokensMinted(uint256 amount, uint256 timestamp);
    event TimeValidation(int256 correctionFactor, uint256 timestamp);
    event MintingToggled(bool enabled);
    event ContractPaused(address indexed by);
    event ContractUnpaused(address indexed by);
    
    constructor() ERC20("TimeTickBase", "TTB") Ownable(msg.sender) {
        genesisTime = block.timestamp;
        lastMintTime = block.timestamp;
        mintingEnabled = false; // Start paused for safety
    }
    
    // Admin functions
    function toggleMinting() external onlyOwner {
        mintingEnabled = !mintingEnabled;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }

    function setDepot(address _depot) external onlyOwner {
        require(_depot != address(0), "Invalid depot address");
        depot = ITimeTickBaseDepot(_depot);
    }
    
    // Core minting function - anyone can call
    function mintTokens() external nonReentrant whenNotPaused {
        require(mintingEnabled, "Minting not enabled");
        require(block.timestamp > lastMintTime, "Already processed");
        
        // Calculate elapsed time and ensure minimum time has passed
        uint256 elapsedTime = block.timestamp - lastMintTime;
        require(elapsedTime >= MINIMUM_MINT_SECONDS, "Minimum mint interval not met");
        
        // Calculate and mint new tokens (1 per second)
        uint256 tokensToMint = elapsedTime * 1 ether; // 1 token per second
        
        _mint(address(this), tokensToMint);
        lastMintTime = block.timestamp;
        
        emit TokensMinted(tokensToMint, block.timestamp);
    }
    
    // Validation function to correct any drift
    function validateTotalTime() external nonReentrant whenNotPaused returns (int256) {
        require(mintingEnabled, "Minting not enabled");
        require(block.timestamp > lastMintTime, "Already processed");
        
        // Ensure minimum time has passed
        uint256 elapsedTime = block.timestamp - lastMintTime;
        require(elapsedTime >= MINIMUM_MINT_SECONDS, "Minimum mint interval not met");
        
        // Calculate normal mint amount
        uint256 normalMint = elapsedTime * 1 ether;
        
        // Calculate expected total based on time since genesis
        uint256 totalElapsedTime = block.timestamp - genesisTime;
        uint256 expectedTotal = totalElapsedTime * 1 ether;
        
        // Calculate correction needed
        uint256 futureSupply = totalSupply() + normalMint;
        int256 correction = int256(expectedTotal) - int256(futureSupply);
        
        // Limit corrections
        if (correction > int256(3600 ether)) {
            correction = int256(3600 ether);
        }
        if (correction < 0 && uint256(-correction) > normalMint) {
            correction = -int256(normalMint);
        }
        
        // Mint tokens with correction
        uint256 adjustedMint = normalMint;
        if (correction > 0) {
            adjustedMint += uint256(correction);
        } else if (correction < 0) {
            adjustedMint -= uint256(-correction);
        }
        
        _mint(address(this), adjustedMint);
        lastMintTime = block.timestamp;
        
        emit TimeValidation(correction, block.timestamp);
        return correction;
    }
    
    // View functions
    function getTokenStats() external view returns (
        uint256 _genesisTime,
        uint256 _lastMintTime,
        uint256 _currentSupply,
        bool _mintingEnabled
    ) {
        return (
            genesisTime,
            lastMintTime,
            totalSupply(),
            mintingEnabled
        );
    }
}