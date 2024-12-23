// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TimeToken is ERC20 {
    // Timing state
    uint256 public lastMintTime;
    uint256 public genesisTime;
    uint256 public batchDuration;

    // Distribution constants
    uint8 private constant NO_KEEPERS_DEV_SHARE = 70;
    uint8 private constant NO_KEEPERS_STABILITY_SHARE = 30;
    uint8 private constant WITH_KEEPERS_DEV_SHARE = 20;
    uint8 private constant WITH_KEEPERS_STABILITY_SHARE = 10;
    uint8 private constant WITH_KEEPERS_VALIDATORS_SHARE = 70;

    // Fund addresses
    address public immutable devFundAddress;
    address public immutable stabilityPoolAddress;
    
    // Distribution totals
    uint256 public devFundTotal;
    uint256 public stabilityPoolTotal;

    // Staking state
    mapping(address => uint256) public stakedDays;  // Days staked by address
    mapping(address => uint256) public stakeStartTime; // When they last staked/unstaked
    address[] private _allStakers;
    uint256 public constant STAKE_UNIT = 86400 ether; // One day in wei

    // Events
    event TokensMinted(address indexed to, uint256 amount, bool validated);
    event SupplyValidation(
        uint256 totalSecondsSinceGenesis,
        uint256 previousSupply,
        uint256 expectedSupply,
        uint256 adjustmentAmount,
        bool validated
    );
    event FundDistribution(
        uint256 devAmount,
        uint256 stabilityAmount,
        uint256 timekeepersAmount,
        uint256 validTimekeepers,
        uint256 timestamp
    );
    event Staked(address indexed staker, uint256 numDays);
    event Unstaked(address indexed staker, uint256 numDays);

    constructor(
        address _devFundAddress,
        address _stabilityPoolAddress,
        uint256 _batchDuration
    ) ERC20("TimeToken", "TTB") {
        require(_devFundAddress != address(0), "Invalid dev fund address");
        require(_stabilityPoolAddress != address(0), "Invalid stability pool address");
        require(_batchDuration > 0, "Batch duration must be positive");
        require(_devFundAddress != _stabilityPoolAddress, "Addresses must be different");

        devFundAddress = _devFundAddress;
        stabilityPoolAddress = _stabilityPoolAddress;
        batchDuration = _batchDuration;

        genesisTime = block.timestamp;
        lastMintTime = block.timestamp;
    }

    function stake(uint256 numberOfDays) external {
        require(numberOfDays > 0, "Must stake at least one day");
        uint256 amount = numberOfDays * STAKE_UNIT;
        
        require(transfer(address(this), amount), "Transfer failed");
        
        if (stakedDays[msg.sender] == 0) {
            _allStakers.push(msg.sender);
        }
        
        stakedDays[msg.sender] = numberOfDays;
        stakeStartTime[msg.sender] = block.timestamp;
        
        emit Staked(msg.sender, numberOfDays);
    }

    function unstake() external {
        uint256 stakedAmount = stakedDays[msg.sender] * STAKE_UNIT;
        require(stakedAmount > 0, "No stake found");
        
        uint256 numDays = stakedDays[msg.sender];
        stakedDays[msg.sender] = 0;
        stakeStartTime[msg.sender] = 0;
        
        require(transfer(msg.sender, stakedAmount), "Transfer failed");
        
        emit Unstaked(msg.sender, numDays);
    }

    function isValidTimekeeper(address account) public view returns (bool) {
        return stakedDays[account] >= 1 && stakeStartTime[account] <= lastMintTime;
    }

    function getValidTimekeepers() internal view returns (address[] memory) {
        uint256 count = 0;
        for(uint256 i = 0; i < _allStakers.length; i++) {
            if(isValidTimekeeper(_allStakers[i])) {
                count++;
            }
        }
        
        address[] memory valid = new address[](count);
        uint256 index = 0;
        for(uint256 i = 0; i < _allStakers.length; i++) {
            if(isValidTimekeeper(_allStakers[i])) {
                valid[index] = _allStakers[i];
                index++;
            }
        }
        
        return valid;
    }

    function mintBatch() public {
        uint256 currentTime = block.timestamp;
        require(currentTime >= lastMintTime + batchDuration, "Batch period not reached");

        uint256 elapsedSeconds = currentTime - lastMintTime;
        uint256 tokensToMint = elapsedSeconds * (1 ether);

        address[] memory validTimekeepers = getValidTimekeepers();
        uint256 timekeeperCount = validTimekeepers.length;
        
        uint256 devAmount;
        uint256 stabilityAmount;
        uint256 timekeepersAmount;
        
        if (timekeeperCount == 0) {
            devAmount = (tokensToMint * NO_KEEPERS_DEV_SHARE) / 100;
            stabilityAmount = (tokensToMint * NO_KEEPERS_STABILITY_SHARE) / 100;
            timekeepersAmount = 0;
        } else {
            devAmount = (tokensToMint * WITH_KEEPERS_DEV_SHARE) / 100;
            stabilityAmount = (tokensToMint * WITH_KEEPERS_STABILITY_SHARE) / 100;
            timekeepersAmount = (tokensToMint * WITH_KEEPERS_VALIDATORS_SHARE) / 100;
            
            uint256 amountPerKeeper = timekeepersAmount / timekeeperCount;
            for(uint256 i = 0; i < timekeeperCount; i++) {
                _mint(validTimekeepers[i], amountPerKeeper);
            }
        }

        _mint(devFundAddress, devAmount);
        _mint(stabilityPoolAddress, stabilityAmount);

        devFundTotal += devAmount;
        stabilityPoolTotal += stabilityAmount;
        
        lastMintTime = currentTime;

        emit TokensMinted(address(this), tokensToMint, false);
        emit FundDistribution(
            devAmount, 
            stabilityAmount, 
            timekeepersAmount,
            timekeeperCount,
            currentTime
        );
    }

    function validateSupply() public view returns (
        bool valid,
        uint256 totalSeconds,
        uint256 expectedSupply,
        uint256 currentSupply,
        uint256 difference
    ) {
        totalSeconds = block.timestamp - genesisTime;
        expectedSupply = totalSeconds * (1 ether);
        currentSupply = totalSupply();

        if (expectedSupply >= currentSupply) {
            difference = expectedSupply - currentSupply;
        } else {
            difference = currentSupply - expectedSupply;
        }

        valid = difference == 0;
        return (valid, totalSeconds, expectedSupply, currentSupply, difference);
    }
}
