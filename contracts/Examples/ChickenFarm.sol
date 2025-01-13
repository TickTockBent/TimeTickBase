// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITTBDualWrapper {
    function mintTokenB(address to, uint256 amount) external;
}

contract ChickenFarm is Ownable, ReentrancyGuard {
    // Token interfaces
    IERC20 public CHKN;
    ITTBDualWrapper public wrapper;

    // Game constants
    uint256 public constant MAX_CHICKENS = 4;
    uint256 public constant CHECK_COOLDOWN = 1 days;
    uint256 public constant MIN_EGGS = 10;   // Minimum eggs per chicken
    uint256 public constant MAX_EGGS = 100;  // Maximum eggs per chicken
    uint256 public constant AVG_EGGS = 30;   // Target average eggs per chicken

    // Farmer data
    struct Farmer {
        uint256 chickensStaked;
        uint256 lastCheckTime;
        uint256 lastStakeChange;
    }
    mapping(address => Farmer) public farmers;

    // Events
    event ChickensStaked(address indexed farmer, uint256 amount);
    event ChickensUnstaked(address indexed farmer, uint256 amount);
    event EggsCollected(address indexed farmer, uint256 amount);

    constructor(
        address _wrapper,
        address _chknToken
    ) Ownable(msg.sender) {
        wrapper = ITTBDualWrapper(_wrapper);
        CHKN = IERC20(_chknToken);
    }

    // Stake CHKNs in the farm
    function stakeChickens(uint256 amount) external nonReentrant {
    require(amount > 0, "Must stake some chickens");

    Farmer storage farmer = farmers[msg.sender];
    // Convert from wei to whole chickens for the check
    uint256 wholeChickens = amount / 1e18;
    require(farmer.chickensStaked + wholeChickens <= MAX_CHICKENS, "Too many chickens");

    // Take CHKN tokens (using full amount with decimals)
    require(CHKN.transferFrom(msg.sender, address(this), amount), "Transfer failed");

    // Update farmer (store whole chickens)
    farmer.chickensStaked += wholeChickens;
    farmer.lastStakeChange = block.timestamp;
    farmer.lastCheckTime = block.timestamp;

    emit ChickensStaked(msg.sender, wholeChickens);
    }

    // Unstake CHKNs from the farm
    function unstakeChickens(uint256 amount) external nonReentrant {
        Farmer storage farmer = farmers[msg.sender];
        require(farmer.chickensStaked >= amount, "Not enough chickens");

        // Return CHKN tokens
        require(CHKN.transfer(msg.sender, amount), "Transfer failed");

        // Update farmer
        farmer.chickensStaked -= amount;
        farmer.lastStakeChange = block.timestamp;
        farmer.lastCheckTime = block.timestamp;

        emit ChickensUnstaked(msg.sender, amount);
    }

    // Check for and collect eggs
    function checkNests() external nonReentrant {
        Farmer storage farmer = farmers[msg.sender];
        require(farmer.chickensStaked > 0, "No chickens staked");
        require(block.timestamp >= farmer.lastCheckTime + CHECK_COOLDOWN, "Too soon to check");
        require(block.timestamp >= farmer.lastStakeChange + CHECK_COOLDOWN, "Must wait after staking");

        uint256 totalEggs;

        // Each chicken lays eggs
        for(uint256 i = 0; i < farmer.chickensStaked; i++) {
            // Use block hash for randomness (yes, it's not perfect but it's just a game)
            uint256 random = uint256(keccak256(abi.encodePacked(
                blockhash(block.number - 1),
                msg.sender,
                i
            )));

            // Calculate eggs laid (between MIN_EGGS and MAX_EGGS)
            uint256 eggs = MIN_EGGS + (random % (MAX_EGGS - MIN_EGGS + 1));
            totalEggs += eggs;
        }

        // Mint eggs to the farmer
        wrapper.mintTokenB(msg.sender, totalEggs);

        // Update last check time
        farmer.lastCheckTime = block.timestamp;

        emit EggsCollected(msg.sender, totalEggs);
    }

    // View functions
    function getFarmerInfo(address _farmer) external view returns (
        uint256 chickensStaked,
        uint256 lastCheckTime,
        uint256 lastStakeChange,
        uint256 timeUntilNextCheck
    ) {
        Farmer memory farmer = farmers[_farmer];
        uint256 nextCheck = farmer.lastCheckTime + CHECK_COOLDOWN;
        uint256 nextStakeCheck = farmer.lastStakeChange + CHECK_COOLDOWN;
        uint256 timeUntil = block.timestamp >= nextCheck ?
            0 : nextCheck - block.timestamp;

        // If stake is more recent, use that timer
        if (nextStakeCheck > nextCheck) {
            timeUntil = block.timestamp >= nextStakeCheck ?
                0 : nextStakeCheck - block.timestamp;
        }

        return (
            farmer.chickensStaked,
            farmer.lastCheckTime,
            farmer.lastStakeChange,
            timeUntil
        );
    }
}
