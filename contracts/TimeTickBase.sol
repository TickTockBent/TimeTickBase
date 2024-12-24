// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TimeToken is ERC20 {
    // Timing / Emission state
    uint256 public lastMintTime;
    uint256 public genesisTime;
    uint256 public batchDuration;

    // Distribution constants (percentages)
    uint8 private constant NO_KEEPERS_DEV_SHARE = 100;
    uint8 private constant WITH_KEEPERS_DEV_SHARE = 30;
    uint8 private constant WITH_KEEPERS_VALIDATORS_SHARE = 70;
    uint256 private constant PERCENT_BASE = 100; // For easier readability

    // Fund address
    address public immutable devFundAddress;

    // Distribution totals
    uint256 public devFundTotal;

    // Staking state (hourly)
    mapping(address => uint256) public stakedHours;
    mapping(address => uint256) public stakeStartTime;

    // Tracks how many stake-hours each address had at the end of the last distribution
    mapping(address => uint256) private _lastBatchStakeHours;

    // Keep track of all stakers
    address[] private _allStakers;

    // One stake-hour = 3600 tokens
    uint256 public constant STAKE_UNIT = 3600 ether;

    // Soft-stop: global minimum stake required, in stake-hour units
    uint256 public minimumStakeUnits;

    //-------------------------------------------------------------------------
    // Events
    //-------------------------------------------------------------------------
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
        uint256 timekeepersAmount,
        uint256 totalMaintainedStakeHours,
        uint256 timestamp
    );
    event Staked(address indexed staker, uint256 numHours);
    event Unstaked(address indexed staker, uint256 numHours);

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    constructor(
        address _devFundAddress,
        uint256 _batchDuration
    ) ERC20("TimeToken", "TTB") {
        require(_devFundAddress != address(0), "Invalid dev fund address");
        require(_batchDuration > 0, "Batch duration must be positive");

        devFundAddress = _devFundAddress;
        batchDuration = _batchDuration;

        genesisTime = block.timestamp;
        lastMintTime = block.timestamp;

        // Default minimum stake is 1 stake-hour (3600 tokens)
        minimumStakeUnits = 1;
    }

    //-------------------------------------------------------------------------
    // Soft-stop setter (no access control here, for local testing convenience)
    //-------------------------------------------------------------------------
    function setMinimumStakeUnits(uint256 newMin) external {
        require(newMin > 0, "Minimum stake must be positive");
        minimumStakeUnits = newMin;
    }

    //-------------------------------------------------------------------------
    // Staking Functions
    //-------------------------------------------------------------------------
    function stake(uint256 stakeHours) external {
        // Must stake at least 'minimumStakeUnits' of stake-hours
        require(stakeHours >= minimumStakeUnits, "Below the current minimum stake requirement");

        // Convert hours to tokens
        uint256 amount = stakeHours * STAKE_UNIT;

        // Transfer TTB from sender to contract
        require(transfer(address(this), amount), "Transfer failed");

        // If first stake for this address, add to _allStakers
        if (stakedHours[msg.sender] == 0) {
            _allStakers.push(msg.sender);
        }

        // Update user's staked hours and stake start time
        stakedHours[msg.sender] = stakeHours;
        stakeStartTime[msg.sender] = block.timestamp;

        emit Staked(msg.sender, stakeHours);
    }

    function unstake() external {
        uint256 currentHours = stakedHours[msg.sender];
        require(currentHours > 0, "No stake found");

        // Convert staked hours to tokens
        uint256 stakedAmount = currentHours * STAKE_UNIT;

        // Reset the user's stake
        stakedHours[msg.sender] = 0;
        stakeStartTime[msg.sender] = 0;

        // Transfer tokens back to the user
        require(transfer(msg.sender, stakedAmount), "Transfer failed");

        emit Unstaked(msg.sender, currentHours);
    }

    //-------------------------------------------------------------------------
    // Unvalidated Batch Mint
    //-------------------------------------------------------------------------
    function mintBatch() external {
        uint256 currentTime = block.timestamp;
        require(currentTime >= lastMintTime + batchDuration, "Batch period not reached");

        // 1) Calculate the total tokens to mint for this batch
        uint256 elapsedSeconds = currentTime - lastMintTime;
        uint256 tokensToMint = elapsedSeconds * (1 ether);

        // 2) Compute how many stake-hours were maintained from last batch to this batch
        uint256 totalMaintainedStakeHours = 0;
        uint256 stakersLength = _allStakers.length;

        uint256[] memory maintained = new uint256[](stakersLength);

        for (uint256 i = 0; i < stakersLength; i++) {
            address staker = _allStakers[i];
            uint256 lastHours = _lastBatchStakeHours[staker];
            uint256 currentHours = stakedHours[staker];

            // Reward = min(lastHours, currentHours)
            uint256 eligibleHours = 0;
            if (lastHours > 0 && currentHours > 0) {
                eligibleHours = (currentHours >= lastHours) ? lastHours : currentHours;
            }

            maintained[i] = eligibleHours;
            totalMaintainedStakeHours += eligibleHours;
        }

        // 3) Distribute minted tokens
        uint256 devAmount;
        uint256 timekeepersAmount;

        if (totalMaintainedStakeHours == 0) {
            // No stakers -> 100% dev
            devAmount = tokensToMint;
            timekeepersAmount = 0;
        } else {
            devAmount = (tokensToMint * WITH_KEEPERS_DEV_SHARE) / PERCENT_BASE;
            timekeepersAmount = (tokensToMint * WITH_KEEPERS_VALIDATORS_SHARE) / PERCENT_BASE;

            // Distribute to timekeepers
            for (uint256 i = 0; i < stakersLength; i++) {
                if (maintained[i] > 0) {
                    uint256 share = (timekeepersAmount * maintained[i]) / totalMaintainedStakeHours;
                    _mint(_allStakers[i], share);
                }
            }
        }

        // Mint dev share
        _mint(devFundAddress, devAmount);

        // Update totals
        devFundTotal += devAmount;

        // 4) Update _lastBatchStakeHours for next round
        for (uint256 i = 0; i < stakersLength; i++) {
            address staker = _allStakers[i];
            _lastBatchStakeHours[staker] = stakedHours[staker];
        }

        // Set lastMintTime
        lastMintTime = currentTime;

        emit TokensMinted(address(this), tokensToMint, false);
        emit FundDistribution(
            devAmount,
            timekeepersAmount,
            totalMaintainedStakeHours,
            currentTime
        );
    }

    //-------------------------------------------------------------------------
    // Validated Batch Mint
    //-------------------------------------------------------------------------
    function mintBatchValidated() external {
        uint256 currentTime = block.timestamp;
        require(currentTime >= lastMintTime + batchDuration, "Batch period not reached");

        // 1) Compute the *expected* total supply since genesis
        uint256 expectedSupply = (currentTime - genesisTime) * (1 ether);
        uint256 currentSupply = totalSupply();

        // 2) Calculate how many tokens we can mint without exceeding the expected supply
        int256 supplyDiff = int256(expectedSupply) - int256(currentSupply);
        uint256 mintedTokens = 0;
        if (supplyDiff > 0) {
            // under-supplied
            mintedTokens = uint256(supplyDiff);
        }
        // else supplyDiff <= 0 => over-supplied, so mintedTokens = 0

        // 3) Stake-hours distribution logic (like in mintBatch)
        uint256 totalMaintainedStakeHours = 0;
        uint256 stakersLength = _allStakers.length;
        uint256[] memory maintained = new uint256[](stakersLength);

        for (uint256 i = 0; i < stakersLength; i++) {
            address staker = _allStakers[i];
            uint256 lastHours = _lastBatchStakeHours[staker];
            uint256 currentHours = stakedHours[staker];

            uint256 eligibleHours = 0;
            if (lastHours > 0 && currentHours > 0) {
                eligibleHours = (currentHours >= lastHours) ? lastHours : currentHours;
            }

            maintained[i] = eligibleHours;
            totalMaintainedStakeHours += eligibleHours;
        }

        // 4) Distribute minted tokens
        uint256 devAmount;
        uint256 timekeepersAmount;

        if (totalMaintainedStakeHours == 0) {
            // no keepers -> 100% dev
            devAmount = mintedTokens;
            timekeepersAmount = 0;
        } else {
            // active keepers -> 30% dev, 70% keepers
            devAmount = (mintedTokens * WITH_KEEPERS_DEV_SHARE) / PERCENT_BASE;
            timekeepersAmount = (mintedTokens * WITH_KEEPERS_VALIDATORS_SHARE) / PERCENT_BASE;

            for (uint256 i = 0; i < stakersLength; i++) {
                if (maintained[i] > 0) {
                    uint256 share = (timekeepersAmount * maintained[i]) / totalMaintainedStakeHours;
                    _mint(_allStakers[i], share);
                }
            }
        }

        // 5) Mint dev share
        if (devAmount > 0) {
            _mint(devFundAddress, devAmount);
            devFundTotal += devAmount;
        }

        // 6) Update lastBatchStakeHours for next cycle
        for (uint256 i = 0; i < stakersLength; i++) {
            address staker = _allStakers[i];
            _lastBatchStakeHours[staker] = stakedHours[staker];
        }

        // 7) Update lastMintTime
        lastMintTime = currentTime;

        // Emit events: validated = true
        emit TokensMinted(address(this), mintedTokens, true);
        emit FundDistribution(
            devAmount,
            timekeepersAmount,
            totalMaintainedStakeHours,
            currentTime
        );
    }

    //-------------------------------------------------------------------------
    // Validation Logic: ensures total supply matches 1 TTB per second
    //-------------------------------------------------------------------------
    function validateSupply()
        external
        view
        returns (
            bool valid,
            uint256 totalSeconds,
            uint256 expectedSupply,
            uint256 currentSupply,
            uint256 difference
        )
    {
        totalSeconds = block.timestamp - genesisTime;
        expectedSupply = totalSeconds * (1 ether);
        currentSupply = totalSupply();

        if (expectedSupply >= currentSupply) {
            difference = expectedSupply - currentSupply;
        } else {
            difference = currentSupply - expectedSupply;
        }

        valid = (difference == 0);
        return (valid, totalSeconds, expectedSupply, currentSupply, difference);
    }

    //-------------------------------------------------------------------------
    // (Optional) Check if user has staked at least 1 stake-hour
    //-------------------------------------------------------------------------
    function isValidTimekeeper(address account) public view returns (bool) {
        return (stakedHours[account] >= 1 && stakeStartTime[account] <= lastMintTime);
    }

    //-------------------------------------------------------------------------
    // (Optional) Return all 'valid' timekeepers
    //-------------------------------------------------------------------------
    function getValidTimekeepers() external view returns (address[] memory) {
        uint256 count;
        for (uint256 i = 0; i < _allStakers.length; i++) {
            if (isValidTimekeeper(_allStakers[i])) {
                count++;
            }
        }

        address[] memory valid = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _allStakers.length; i++) {
            if (isValidTimekeeper(_allStakers[i])) {
                valid[index] = _allStakers[i];
                index++;
            }
        }
        return valid;
    }
}