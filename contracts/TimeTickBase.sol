// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TimeTickBase
 * @dev ERC20 token representing time units.
 */

// Why is this contract called TimeTickBase?
// Because it's the same initials as my username
// Seriously, that's it
// I'm not that creative
// It's still a good idea though
// And it's a good name
// So I'm keeping it

contract TimeToken is ERC20, ReentrancyGuard, Pausable, Ownable {
    // Timing / Emission state
    uint256 public lastMintTime;
    uint256 public genesisTime;
    uint256 public batchDuration;

    // Distribution constants
    uint8 private constant NO_KEEPERS_DEV_SHARE = 100;
    uint8 private constant WITH_KEEPERS_DEV_SHARE = 30;
    uint8 private constant WITH_KEEPERS_VALIDATORS_SHARE = 70;
    uint256 private constant PERCENT_BASE = 100;

    // Fund address
    address public immutable devFundAddress;
    uint256 public devFundTotal;

    // Staking state
    mapping(address => uint256) public currentStakes;     // Stake units (3600 TTB each)
    mapping(address => uint256) public accruedStakeHours; // Proportional hours accumulated
    mapping(address => uint256) public stakeStartTime;
    uint256 public totalNetworkStakes;

    // Staker tracking with efficient removal
    mapping(address => uint256) private stakerIndices;  // Maps address to array index + 1
    address[] private stakers;

    // Stake change tracking
    enum ChangeType {
        NONE,
        STAKE_ADD,
        STAKE_REMOVE
    }

    struct StateChange {
        uint256 amount;
        uint256 requestTime;
        uint256 processTime;
        ChangeType changeType;
    }

    struct HourBoundary {
        uint256 hour;
        bool queued;
    }

    mapping(address => StateChange) public pendingChanges;
    HourBoundary public nextBoundary;

    // Constants
    uint256 public constant STAKE_UNIT = 3600 ether;
    uint256 public constant UNSTAKE_DELAY = 3 days;
    uint256 public minimumStakeUnits;
    bool public globalStakeLock;

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
        uint256 timekeepersAmount,
        uint256 totalMaintainedStakeHours,
        uint256 timestamp
    );
    event Staked(address indexed staker, uint256 numHours);
    event Unstaked(address indexed staker, uint256 numHours);
    event StakeRequested(
        address indexed staker, 
        uint256 amount, 
        uint256 processTime
    );
    event UnstakeRequested(
        address indexed staker, 
        uint256 amount, 
        uint256 processTime
    );

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
        minimumStakeUnits = 1;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        require(sender != address(0), "Transfer from zero");
        require(recipient != address(0), "Transfer to zero");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "Transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _removeStaker(address staker) internal {
        uint256 index = stakerIndices[staker];
        require(index > 0, "Not a staker");
        index--;

        address lastStaker = stakers[stakers.length - 1];

        if (staker != lastStaker) {
            stakers[index] = lastStaker;
            stakerIndices[lastStaker] = index + 1;
        }

        stakers.pop();
        delete stakerIndices[staker];
    }

    function _addStaker(address staker) internal {
        if (stakerIndices[staker] == 0) {
            stakers.push(staker);
            stakerIndices[staker] = stakers.length;
        }
    }

    function _queueNextHourBoundary() internal {
        uint256 currentHour = block.timestamp / 3600;
        uint256 currentSecond = block.timestamp % 3600;
        
        uint256 targetHour = currentHour + 
            (currentSecond >= 3570 ? 2 : 1);

        if (!nextBoundary.queued || targetHour > nextBoundary.hour) {
            nextBoundary = HourBoundary(targetHour, true);
        }
    }

    function _processHourBoundary() internal nonReentrant {
        uint256 currentHour = block.timestamp / 3600;
        if (nextBoundary.queued && currentHour >= nextBoundary.hour) {
            // First distribute rewards based on current stakes
            for (uint256 i = 0; i < stakers.length; i++) {
                address staker = stakers[i];
                if (currentStakes[staker] > 0) {
                    accruedStakeHours[staker] += 
                        (currentStakes[staker] * PERCENT_BASE) / totalNetworkStakes;
                }
            }

            // Then process pending changes
            for (uint256 i = 0; i < stakers.length; i++) {
                address staker = stakers[i];
                StateChange memory pending = pendingChanges[staker];

                if (pending.changeType != ChangeType.NONE && block.timestamp >= pending.processTime) {
                    if (pending.changeType == ChangeType.STAKE_ADD) {
                        uint256 stakeUnits = pending.amount / STAKE_UNIT;
                        currentStakes[staker] += stakeUnits;
                        totalNetworkStakes += stakeUnits;
                        _addStaker(staker);
                        stakeStartTime[staker] = block.timestamp;
                        _transfer(staker, address(this), pending.amount);
                        emit Staked(staker, stakeUnits);
                    } else {
                        uint256 stakeUnits = pending.amount / STAKE_UNIT;
                        currentStakes[staker] -= stakeUnits;
                        totalNetworkStakes -= stakeUnits;
                        if (currentStakes[staker] == 0) {
                            _removeStaker(staker);
                            stakeStartTime[staker] = 0;
                        }
                        _transfer(address(this), staker, pending.amount);
                        emit Unstaked(staker, stakeUnits);
                    }
                    delete pendingChanges[staker];
                }
            }

            nextBoundary.queued = false;
        }
    }

    function requestStake(uint256 stakeUnits) external whenNotPaused {
        require(!globalStakeLock, "Staking locked");
        require(stakeUnits >= minimumStakeUnits, "Below minimum stake");
        require(pendingChanges[msg.sender].changeType == ChangeType.NONE, "Change pending");

        uint256 amount = stakeUnits * STAKE_UNIT;
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _queueNextHourBoundary();
        
        uint256 processTime = block.timestamp + 3600;
        pendingChanges[msg.sender] = StateChange({
            amount: amount,
            requestTime: block.timestamp,
            processTime: processTime,
            changeType: ChangeType.STAKE_ADD
        });

        emit StakeRequested(msg.sender, amount, processTime);
    }

    function requestUnstake(uint256 stakeUnits) external whenNotPaused {
        require(currentStakes[msg.sender] >= stakeUnits, "Insufficient stake");
        require(pendingChanges[msg.sender].changeType == ChangeType.NONE, "Change pending");

        uint256 remainingStake = currentStakes[msg.sender] - stakeUnits;
        require(
            remainingStake >= minimumStakeUnits || remainingStake == 0,
            "Would fall below minimum"
        );

        uint256 amount = stakeUnits * STAKE_UNIT;
        
        _queueNextHourBoundary();

        uint256 processTime = block.timestamp + UNSTAKE_DELAY;
        pendingChanges[msg.sender] = StateChange({
            amount: amount,
            requestTime: block.timestamp,
            processTime: processTime,
            changeType: ChangeType.STAKE_REMOVE
        });

        emit UnstakeRequested(msg.sender, amount, processTime);
    }

    function mintBatch() external whenNotPaused nonReentrant {
        uint256 currentTime = block.timestamp;
        require(currentTime >= lastMintTime + batchDuration, "Batch period not reached");

        uint256 elapsedSeconds = currentTime - lastMintTime;
        uint256 tokensToMint = elapsedSeconds * (1 ether);

        uint256 totalMaintainedStakeHours = 0;
        uint256 stakersLength = stakers.length;

        uint256[] memory maintained = new uint256[](stakersLength);

        for (uint256 i = 0; i < stakersLength; i++) {
            address staker = stakers[i];
            uint256 lastHours = _lastBatchStakeHours[staker];
            uint256 currentHours = currentStakes[staker];

            uint256 eligibleHours = 0;
            if (lastHours > 0 && currentHours > 0) {
                eligibleHours = (currentHours >= lastHours) ? lastHours : currentHours;
            }

            maintained[i] = eligibleHours;
            totalMaintainedStakeHours += eligibleHours;
        }

        uint256 devAmount;
        uint256 timekeepersAmount;

        if (totalMaintainedStakeHours == 0) {
            devAmount = tokensToMint;
            timekeepersAmount = 0;
        } else {
            devAmount = (tokensToMint * WITH_KEEPERS_DEV_SHARE) / PERCENT_BASE;
            timekeepersAmount = (tokensToMint * WITH_KEEPERS_VALIDATORS_SHARE) / PERCENT_BASE;

            for (uint256 i = 0; i < stakersLength; i++) {
                if (maintained[i] > 0) {
                    uint256 share = (timekeepersAmount * maintained[i]) / totalMaintainedStakeHours;
                    _mint(stakers[i], share);
                }
            }
        }

        _mint(devFundAddress, devAmount);
        devFundTotal += devAmount;

        for (uint256 i = 0; i < stakersLength; i++) {
            address staker = stakers[i];
            _lastBatchStakeHours[staker] = currentStakes[staker];
        }

        lastMintTime = currentTime;

        emit TokensMinted(address(this), tokensToMint, false);
        emit FundDistribution(
            devAmount,
            timekeepersAmount,
            totalMaintainedStakeHours,
            currentTime
        );
    }

    function mintBatchValidated() external whenNotPaused nonReentrant {
        uint256 currentTime = block.timestamp;
        require(currentTime >= lastMintTime + batchDuration, "Batch period not reached");

        uint256 expectedSupply = (currentTime - genesisTime) * (1 ether);
        uint256 currentSupply = totalSupply();

        int256 supplyDiff = int256(expectedSupply) - int256(currentSupply);
        uint256 mintedTokens = 0;
        if (supplyDiff > 0) {
            mintedTokens = uint256(supplyDiff);
        }

        uint256 totalMaintainedStakeHours = 0;
        uint256 stakersLength = stakers.length;
        uint256[] memory maintained = new uint256[](stakersLength);

        for (uint256 i = 0; i < stakersLength; i++) {
            address staker = stakers[i];
            uint256 lastHours = _lastBatchStakeHours[staker];
            uint256 currentHours = currentStakes[staker];

            uint256 eligibleHours = 0;
            if (lastHours > 0 && currentHours > 0) {
                eligibleHours = (currentHours >= lastHours) ? lastHours : currentHours;
            }

            maintained[i] = eligibleHours;
            totalMaintainedStakeHours += eligibleHours;
        }

        uint256 devAmount;
        uint256 timekeepersAmount;

        if (totalMaintainedStakeHours == 0) {
            devAmount = mintedTokens;
            timekeepersAmount = 0;
        } else {
            devAmount = (mintedTokens * WITH_KEEPERS_DEV_SHARE) / PERCENT_BASE;
            timekeepersAmount = (mintedTokens * WITH_KEEPERS_VALIDATORS_SHARE) / PERCENT_BASE;

            for (uint256 i = 0; i < stakersLength; i++) {
                if (maintained[i] > 0) {
                    uint256 share = (timekeepersAmount * maintained[i]) / totalMaintainedStakeHours;
                    _mint(stakers[i], share);
                }
            }
        }

        if (devAmount > 0) {
            _mint(devFundAddress, devAmount);
            devFundTotal += devAmount;
        }

        for (uint256 i = 0; i < stakersLength; i++) {
            address staker = stakers[i];
            _lastBatchStakeHours[staker] = currentStakes[staker];
        }

        lastMintTime = currentTime;

        emit TokensMinted(address(this), mintedTokens, true);
        emit FundDistribution(
            devAmount,
            timekeepersAmount,
            totalMaintainedStakeHours,
            currentTime
        );
    }

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

    function isValidTimekeeper(address account) public view returns (bool) {
        return currentStakes[account] > 0;
    }

    function getValidTimekeepers() external view returns (address[] memory) {
        uint256 count;
        for (uint256 i = 0; i < stakers.length; i++) {
            if (isValidTimekeeper(stakers[i])) {
                count++;
            }
        }

        address[] memory valid = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < stakers.length; i++) {
            if (isValidTimekeeper(stakers[i])) {
                valid[index] = stakers[i];
                index++;
            }
        }
        return valid;
    }

    // Pausable functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}