// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "hardhat/console.sol";

contract TimeTickBase is ERC20, ReentrancyGuard, Ownable, Pausable {

    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant STAKE_UNIT = 3600 ether;  // 1 stake = 3600 TTB
    uint256 public constant UNSTAKE_DELAY = 3 days;
    uint256 public constant RENEWAL_PERIOD = 180 days;
    uint256 private constant PRECISION = 1e18;
    uint256 public genesisTime;
    uint256 public lastMintTime;
    uint256 private constant DEV_SHARE = 30;   
    uint256 private constant STAKER_SHARE = 70;

    bool public rewardsEnabled;
    bool public stakingEnabled;

    struct Staker {
        uint256 stakedAmount;          // Amount of TTB staked
        uint256 unclaimedRewards;      // Pending rewards
        uint256 lastRenewalTime;       // Last renewal timestamp
        uint256 unstakeTime;           // When tokens can be unstaked (0 if no pending unstake)
    }
    
    mapping(address => Staker) public stakers;
    uint256 public totalStaked;
    uint256 public minimumStake;
    address public immutable devFundAddress;

    EnumerableSet.AddressSet private stakerSet;

    event Staked(address indexed staker, uint256 amount);
    event UnstakeRequested(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event RewardsClaimed(address indexed staker, uint256 amount);
    event StakeRenewed(address indexed staker);
    event StakeExpired(address indexed staker, uint256 amount, uint256 rewards);
    event TimeValidation(int256 correctionFactor);
    event RewardsProcessed(uint256 totalRewards, uint256 devShare, uint256 stakerShare, int256 correctionFactor, bool validated);
    event UnstakeCancelled(address indexed staker, uint256 amount);
    event MinimumStakeUpdated(uint256 newMinimum);
    event StakingToggled(bool enabled);
    event RewardsToggled(bool enabled);
    event DebugStaking(string message, uint256 value);
    event DebugStaking(string message);

    constructor(address _devFundAddress) ERC20("TimeTickBase", "TTB") Ownable(msg.sender) {
        require(_devFundAddress != address(0), "Invalid dev fund address");
        devFundAddress = _devFundAddress;
        genesisTime = block.timestamp;
        lastMintTime = block.timestamp;
        minimumStake = STAKE_UNIT;  // Start with 1 stake minimum

        rewardsEnabled = false;
        stakingEnabled = false;
    }

    function setMinimumStake(uint256 _newMinimum) external onlyOwner {
        require(_newMinimum >= STAKE_UNIT, "Below stake unit");
        require(_newMinimum % STAKE_UNIT == 0, "Must be whole units");
        minimumStake = _newMinimum;
        emit MinimumStakeUpdated(_newMinimum);
    }
    
    function toggleStaking() external onlyOwner {
        stakingEnabled = !stakingEnabled;
        emit StakingToggled(stakingEnabled);
    }
    
    function toggleRewards() external onlyOwner {
        rewardsEnabled = !rewardsEnabled;
        emit RewardsToggled(rewardsEnabled);
    }

    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }

    function stake(uint256 amount) external nonReentrant whenNotPaused {
        emit DebugStaking("Stake called with amount", amount);
        console.log("Staking called by: ", msg.sender);
        
        require(stakingEnabled, "Staking not enabled");
        emit DebugStaking("Staking is enabled");
        console.log("Staking is enabled");

        require(amount >= minimumStake, "Below minimum stake");
        emit DebugStaking("Amount meets minimum stake");
        console.log("Amount meets minimum stake");
        
        require(amount % STAKE_UNIT == 0, "Must stake whole units");
        emit DebugStaking("Amount is valid stake unit");
        console.log("Amount is valid stake unit");
        
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime == 0, "Unstake pending");
        emit DebugStaking("No unstake pending");
        console.log("No unstake pending");
        
        // Check balance before transfer
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        emit DebugStaking("Balance check passed");
        console.log("Balance check passed");
        
        // Check allowance before transfer
        require(allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");
        emit DebugStaking("Allowance check passed");
        console.log("Allowance check passed");
        
        console.log("Balance before transfer:", balanceOf(msg.sender));
        console.log("Amount to transfer:", amount);
        console.log("Current allowance:", allowance(msg.sender, address(this)));
        emit DebugStaking("Balance before transfer", balanceOf(msg.sender));
        emit DebugStaking("Amount to transfer", amount);
        emit DebugStaking("Current allowance", allowance(msg.sender, address(this)));
        _spendAllowance(msg.sender, address(this), amount);
        _transfer(msg.sender, address(this), amount);
        console.log("Balance after transfer:", balanceOf(msg.sender));
        emit DebugStaking("Balance after transfer", balanceOf(msg.sender));
        
        staker.stakedAmount += amount;
        staker.lastRenewalTime = block.timestamp;
        totalStaked += amount;
        
        if (staker.stakedAmount == amount) {
            stakerSet.add(msg.sender);
        }
        
        emit Staked(msg.sender, amount);
    }
    
    function requestUnstake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.stakedAmount > 0, "No stake found");
        require(staker.unstakeTime == 0, "Unstake already pending");
        
        staker.unstakeTime = block.timestamp + UNSTAKE_DELAY;
        
        emit UnstakeRequested(msg.sender, staker.stakedAmount);
    }
    
    function unstake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime > 0 && block.timestamp >= staker.unstakeTime, "Not ready");
        
        uint256 amount = staker.stakedAmount;

        totalStaked -= amount;
        staker.stakedAmount = 0;
        staker.unstakeTime = 0;
        staker.lastRenewalTime = 0;
        
        stakerSet.remove(msg.sender);
        
        if (staker.unclaimedRewards > 0) {
            uint256 rewards = staker.unclaimedRewards;
            staker.unclaimedRewards = 0;
            _transfer(address(this), msg.sender, rewards);
            emit RewardsClaimed(msg.sender, rewards);
        }
        
        _transfer(address(this), msg.sender, amount);
        
        emit Unstaked(msg.sender, amount);
    }
    
    function cancelUnstake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime > 0, "No unstake request");
        require(staker.stakedAmount > 0, "No stake found");
        
        staker.unstakeTime = 0;
        
        emit UnstakeCancelled(msg.sender, staker.stakedAmount);
    }

    function renewStake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.stakedAmount > 0, "No stake found");
        require(block.timestamp <= staker.lastRenewalTime + RENEWAL_PERIOD, "Stake expired");
        
        // Force claim rewards on renewal
        if (staker.unclaimedRewards > 0) {
            uint256 rewards = staker.unclaimedRewards;
            staker.unclaimedRewards = 0;
            _transfer(address(this), msg.sender, rewards);
            emit RewardsClaimed(msg.sender, rewards);
        }
        
        staker.lastRenewalTime = block.timestamp;
        emit StakeRenewed(msg.sender);
    }

    function claimRewards() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unclaimedRewards > 0, "No rewards to claim");
        
        uint256 rewards = staker.unclaimedRewards;
        staker.unclaimedRewards = 0;
        _transfer(address(this), msg.sender, rewards);
        
        emit RewardsClaimed(msg.sender, rewards);
    }

    function _processExpiredStakes() internal {
        if (stakerSet.length() == 0) return;
        
        address[] memory _stakers = stakerSet.values();
        
        for (uint256 i = 0; i < _stakers.length; i++) {
            address stakerAddr = _stakers[i];
            Staker storage staker = stakers[stakerAddr];
            
            if (staker.stakedAmount > 0 && 
                block.timestamp > staker.lastRenewalTime + RENEWAL_PERIOD) {
                
                uint256 amount = staker.stakedAmount;
                uint256 rewards = staker.unclaimedRewards;
                
                totalStaked -= amount;
                staker.stakedAmount = 0;
                staker.unclaimedRewards = 0;
                staker.lastRenewalTime = 0;
                
                stakerSet.remove(stakerAddr);
                
                _transfer(address(this), stakerAddr, amount + rewards);
                
                emit StakeExpired(stakerAddr, amount, rewards);
            }
        }
    }
    
    function processRewards() external nonReentrant whenNotPaused {
        require(rewardsEnabled, "Rewards not enabled");
        _processRewardsAndValidation(0);
    }
    
    function _processRewardsAndValidation(int256 correctionFactor) internal {
        require(block.timestamp > lastMintTime, "Already processed");
        
        _processExpiredStakes();
        
        uint256 elapsedTime = block.timestamp - lastMintTime;
        uint256 tokensToMint = elapsedTime * 1 ether;
        
        if (correctionFactor > 0) {
            tokensToMint += uint256(correctionFactor);
        } else if (correctionFactor < 0) {
            tokensToMint -= uint256(-correctionFactor);
        }
        
        _mint(address(this), tokensToMint);
        
        uint256 devRewards = (tokensToMint * DEV_SHARE) / 100;
        uint256 stakerRewards = tokensToMint - devRewards;
        
        if (totalStaked > 0) {
            address[] memory _stakers = stakerSet.values();
            for (uint256 i = 0; i < _stakers.length; i++) {
                address stakerAddr = _stakers[i];
                Staker storage staker = stakers[stakerAddr];
                
                if (staker.stakedAmount > 0) {
                    // Calculate proportion first to maintain precision
                    uint256 proportion = (staker.stakedAmount * PRECISION) / totalStaked;
                    uint256 share = (stakerRewards * proportion) / PRECISION;
                    staker.unclaimedRewards += share;
                }
            }
        } else {
            devRewards += stakerRewards;
        }

        _transfer(address(this), devFundAddress, devRewards);
        
        lastMintTime = block.timestamp;
        
        emit RewardsProcessed(tokensToMint, devRewards, stakerRewards, correctionFactor, correctionFactor != 0);
    }

    function validateTotalTime() external nonReentrant returns (int256) {
        uint256 elapsedTime = block.timestamp - lastMintTime;
        uint256 normalMint = elapsedTime * 1 ether;

        uint256 expectedSupply = totalSupply() + normalMint;
        
        uint256 totalElapsedTime = block.timestamp - genesisTime;
        uint256 correctSupply = totalElapsedTime * 1 ether;
        
        int256 correction = int256(correctSupply) - int256(expectedSupply);
        
        if (correction > int256(3600 ether)) {
            correction = int256(3600 ether);
        }
        
        if (correction < 0) {
            if (uint256(-correction) > normalMint) {
                correction = -int256(normalMint);
            }
        }
        
        emit TimeValidation(correction);
        _processRewardsAndValidation(correction);
               
        return correction;
    }

    function getStakerInfo(address staker) external view returns (
        uint256 stakedAmount,
        uint256 unclaimedRewards,
        uint256 lastRenewalTime,
        uint256 unstakeTime
    ) {
        Staker storage s = stakers[staker];
        return (s.stakedAmount, s.unclaimedRewards, s.lastRenewalTime, s.unstakeTime);
    }

    function getNetworkStats() external view returns (
        uint256 totalStakedAmount,
        uint256 totalStakers,
        uint256 rewardRate,  // Will be 1 ether (1e18) per second
        uint256 minimumStakeRequired
    ) {
        return (
            totalStaked,
            stakerSet.length(),
            1 ether,
            minimumStake
        );
    }
}