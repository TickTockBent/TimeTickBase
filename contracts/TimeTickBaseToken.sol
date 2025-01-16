// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface ITimeTickBaseDepot {
    function processNewMint(uint256 amount) external;
}

contract TimeTickBaseToken is ERC20, ReentrancyGuard, Ownable, Pausable {
    // Immutable time tracking and mint rate
    uint256 public immutable genesisTime;
    uint256 public lastMintTime;
    uint256 public constant MINIMUM_MINT_SECONDS = 15;
    uint256 public constant MINT_RATE_PER_SECOND = 1 ether; // Fixed mint rate

    // Reference to the TimeTickBaseDepot contract
    address public depot;

    // Admin control for pausing/unpausing and setting depot
    bool public mintingEnabled;

    // Events
    event TokensMinted(uint256 amount, uint256 timestamp);
    event TimeValidation(int256 correctionFactor, uint256 timestamp);
    event MintingToggled(bool enabled);
    event DepotSet(address newDepot);
    event ContractPaused(address indexed by);
    event ContractUnpaused(address indexed by);


    constructor() ERC20("TimeTickBase", "TTB") Ownable(msg.sender) {
        genesisTime = block.timestamp;
        lastMintTime = block.timestamp;
        mintingEnabled = true; // Start enabled
    }

    // Admin functions
    function toggleMinting() external onlyOwner {
        mintingEnabled = !mintingEnabled;
        emit MintingToggled(mintingEnabled);
    }

    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    function setDepot(address _depot) external onlyOwner {
        require(_depot != address(0), "Invalid depot address");
        depot = _depot;
        emit DepotSet(_depot);
    }

    // Minting function - ONLY callable by the Depot
    function mint() external nonReentrant whenNotPaused {
        require(msg.sender == depot, "Only depot can mint");
        require(mintingEnabled, "Minting not enabled");
        require(block.timestamp > lastMintTime, "Already processed");

        // Calculate elapsed time and ensure minimum time has passed
        uint256 elapsedTime = block.timestamp - lastMintTime;
        require(elapsedTime >= MINIMUM_MINT_SECONDS, "Minimum mint interval not met");

        // Calculate and mint new tokens (fixed rate)
        uint256 tokensToMint = elapsedTime * MINT_RATE_PER_SECOND;

        _mint(address(this), tokensToMint); // Mint to THIS contract
        lastMintTime = block.timestamp;

        emit TokensMinted(tokensToMint, block.timestamp);
    }

    // Validation function to correct any drift - ONLY callable by the Depot
    function validateTotalTime() external nonReentrant whenNotPaused returns (int256) {
        require(msg.sender == depot, "Only depot can call this function");
        require(mintingEnabled, "Minting not enabled");
        require(block.timestamp > lastMintTime, "Already processed");

        // Ensure minimum time has passed
        uint256 elapsedTime = block.timestamp - lastMintTime;
        require(elapsedTime >= MINIMUM_MINT_SECONDS, "Minimum mint interval not met");

        // Calculate normal mint amount
        uint256 normalMint = elapsedTime * MINT_RATE_PER_SECOND;

        // Calculate expected total based on time since genesis
        uint256 totalElapsedTime = block.timestamp - genesisTime;
        uint256 expectedTotal = totalElapsedTime * MINT_RATE_PER_SECOND;

        // Calculate correction needed
        uint256 futureSupply = totalSupply() + normalMint;
        int256 correction = int256(expectedTotal) - int256(futureSupply);

        // Limit corrections (same logic as before)
        if (correction > int256(3600 ether)) {
            correction = int256(3600 ether);
        }
        if (correction < 0 && uint256(-correction) > normalMint) {
            correction = -int256(normalMint);
        }

        // Mint tokens with correction to THIS contract
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

    // View functions (unchanged)
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