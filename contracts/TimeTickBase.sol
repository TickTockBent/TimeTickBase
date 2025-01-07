// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract TimeTickBase is ERC20, ReentrancyGuard {

    // Some people asked why I named it TimeTickBase
    // It's because it has the same initials as my username, TTB
    // And it's a time-based token, so TimeTickBase
    // I'm not very creative with names, sorry
    // But I hope you like it anyway
    // - TTB

    using EnumerableSet for EnumerableSet.AddressSet;
    // Core state
    // Genesis time is when the contract was deployed
    // Last mint time is when the last reward was processed
    // Stake unit is the amount of TTB required to stake
    // Unstake delay is the time required to wait before unstaking
    // Renewal period is the time required to renew a stake
    // Precision is used for calculations (might be overkill)

    uint256 public immutable genesisTime;
    uint256 public lastMintTime;
    uint256 public constant STAKE_UNIT = 3600 ether;  // 1 stake = 3600 TTB
    uint256 public constant UNSTAKE_DELAY = 3 days;
    uint256 public constant RENEWAL_PERIOD = 180 days;
    uint256 private constant PRECISION = 1e18;
    
    // Distribution constants
    // Dev share is the percentage of rewards going to the dev fund
    // Staker share is the percentage of rewards going to stakers
    // The sum of both should be 100%
    // This is probably obvious but I'm explaining it anyway

    uint8 private constant DEV_SHARE = 30;   
    uint8 private constant STAKER_SHARE = 70;
    
    // Staker struct

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

    // Staker tracking
    EnumerableSet.AddressSet private stakerSet;
    
    // Events
    event Staked(address indexed staker, uint256 amount);
    event UnstakeRequested(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event RewardsClaimed(address indexed staker, uint256 amount);
    event StakeRenewed(address indexed staker);
    event StakeExpired(address indexed staker, uint256 amount, uint256 rewards);
    event TimeValidation(int256 correctionFactor);
    event RewardsProcessed(uint256 totalRewards, uint256 devShare, uint256 stakerShare, int256 correctionFactor, bool validated);
    
    constructor(address _devFundAddress) ERC20("TimeTickBase", "TTB") {
        require(_devFundAddress != address(0), "Invalid dev fund address");
        devFundAddress = _devFundAddress;
        genesisTime = block.timestamp;
        lastMintTime = block.timestamp;
        minimumStake = STAKE_UNIT;  // Start with 1 stake minimum
    }
    
    // Staking functions
    // Staking requires a minimum amount of TTB
    // Staking is done in whole units of STAKE_UNIT
    // Staking is subject to unstake delay and renewal period
    // Staking rewards are processed periodically

    function stake(uint256 amount) external nonReentrant {
        require(amount >= minimumStake, "Below minimum stake");
        require(amount % STAKE_UNIT == 0, "Must stake whole units");
        
        // Check and process any expired stakes before adding new ones
        _processExpiredStakes();
        
        // Transfer tokens to contract
        require(transfer(address(this), amount), "Transfer failed");
        
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime == 0, "Unstake pending");
        
        // Update stake
        staker.stakedAmount += amount;
        staker.lastRenewalTime = block.timestamp;
        totalStaked += amount;
        
        // Add to staker set if new staker
        if (staker.stakedAmount == amount) { // Previously zero
            stakerSet.add(msg.sender);
        }
        
        emit Staked(msg.sender, amount);
    }
    
    // Request unstake
    function requestUnstake(uint256 amount) external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.stakedAmount >= amount, "Insufficient stake");
        require(staker.unstakeTime == 0, "Unstake already pending");
        require(amount % STAKE_UNIT == 0, "Must unstake whole units");
        
        staker.unstakeTime = block.timestamp + UNSTAKE_DELAY;
        
        emit UnstakeRequested(msg.sender, amount);
    }
    
    // Complete unstake after delay
    function unstake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime > 0 && block.timestamp >= staker.unstakeTime, "Not ready");
        
        uint256 amount = staker.stakedAmount;
        
        // Clear stake
        totalStaked -= amount;
        staker.stakedAmount = 0;
        staker.unstakeTime = 0;
        staker.lastRenewalTime = 0;
        
        // Remove from staker set
        stakerSet.remove(msg.sender);
        
        // Force claim any pending rewards
        if (staker.unclaimedRewards > 0) {
            uint256 rewards = staker.unclaimedRewards;
            staker.unclaimedRewards = 0;
            require(transfer(msg.sender, rewards), "Reward transfer failed");
            emit RewardsClaimed(msg.sender, rewards);
        }
        
        // Return staked tokens
        require(transfer(msg.sender, amount), "Stake transfer failed");
        
        emit Unstaked(msg.sender, amount);
    }
    
    // Renew stake
    function renewStake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.stakedAmount > 0, "No stake found");
        require(block.timestamp <= staker.lastRenewalTime + RENEWAL_PERIOD, "Stake expired");
        
        // Force claim rewards on renewal
        if (staker.unclaimedRewards > 0) {
            uint256 rewards = staker.unclaimedRewards;
            staker.unclaimedRewards = 0;
            require(transfer(msg.sender, rewards), "Reward transfer failed");
            emit RewardsClaimed(msg.sender, rewards);
        }
        
        staker.lastRenewalTime = block.timestamp;
        emit StakeRenewed(msg.sender);
    }
    
    // Claim rewards
    // Rewards are claimed separately from staking

    function claimRewards() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unclaimedRewards > 0, "No rewards to claim");
        
        uint256 rewards = staker.unclaimedRewards;
        staker.unclaimedRewards = 0;
        require(transfer(msg.sender, rewards), "Transfer failed");
        
        emit RewardsClaimed(msg.sender, rewards);
    }
    
    // Process any expired stakes
    // This is done before any reward processing
    // Expired stakes are returned to stakers
    // This is mostly here to prevent dead stakes
    // Proof of life, if you will
    // It's also a good way to clean up the staker set

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
                
                // Clear stake
                totalStaked -= amount;
                staker.stakedAmount = 0;
                staker.unclaimedRewards = 0;
                staker.lastRenewalTime = 0;
                
                // Remove from staker set
                stakerSet.remove(stakerAddr);
                
                // Return tokens (stake + rewards)
                require(transfer(stakerAddr, amount + rewards), "Transfer failed");
                
                emit StakeExpired(stakerAddr, amount, rewards);
            }
        }
    }
    
    // Regular reward processing - public interface
    // This is called by anyone to process rewards
    // Later this will be locked down to a specific address
    // It will be called externally by a time-based trigger
    // I'll probably add a governance system for this in case I die or something
    // Or in case I hand it off to someone else
    // BTW I'm not planning to die but you never know
    // - TTB

    function processRewards() external {
        _processRewardsAndValidation(0);
    }
    
    // Internal implementation
    function _processRewardsAndValidation(int256 correctionFactor) internal nonReentrant {
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
        
        // Calculate shares
        uint256 devRewards = (tokensToMint * DEV_SHARE) / 100;
        uint256 stakerRewards = tokensToMint - devRewards;
        
        // Send dev share
        require(transfer(devFundAddress, devRewards), "Dev transfer failed");
        
        // Distribute staker share if there are stakers
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
        }
        
        lastMintTime = block.timestamp;
        
        emit RewardsProcessed(tokensToMint, devRewards, stakerRewards, correctionFactor, correctionFactor != 0);
    }

    function validateTotalTime() external nonReentrant returns (int256) {
        uint256 totalElapsedTime = block.timestamp - genesisTime;
        uint256 expectedSupply = totalElapsedTime * 1 ether;
        uint256 currentSupply = totalSupply();
        
        int256 correction = int256(expectedSupply) - int256(currentSupply);
        
        // Limit maximum positive correction to 1 hour of tokens
        if (correction > int256(3600 ether)) {
            correction = int256(3600 ether);
        }
        
        // Ensure correction won't result in negative emissions
        if (correction < 0) {
            uint256 elapsedTime = block.timestamp - lastMintTime;
            uint256 expectedEmission = elapsedTime * 1 ether;
            if (uint256(-correction) > expectedEmission) {
                correction = -int256(expectedEmission);
            }
        }
        
        if (correction != 0) {
            emit TimeValidation(correction);
            _processRewardsAndValidation(correction);
        }
        
        return correction;
    }

    // Why are you still reading this?
    // Go stake some TTB and earn rewards
    // Or go build something cool, that's the point of this
    // I'm just here to help you get started
    // - TTB

    // P.S. I'm not a financial advisor
    // This is not financial advice
    // I'm just a developer who likes to build stuff
    // So please don't sue me if you lose money
    // I'm not responsible for your decisions
    // You're a grown-up, you can make your own choices
    // - TTB

    // P.P.S. If you have any questions, feel free to ask
    // I'm happy to help if I can
    // contact@timetickbase.com
    // - TTB

    // P.P.P.S. I'm not planning to die
    // I'm just saying you never know
    // - TTB

    // P.P.P.P.S. I'm not planning to hand this off to anyone either
    // I'm just saying you never know
    // - TTB    

    // P.P.P.P.P.S. You're still reading this?
    // Seriously, go do something else
    // But thanks for reading this far
    // I appreciate it
    // Here's a cookie for you 🍪
    // And an ascii cat
    //  /\_/\
    // ( o.o ) meow
    //  > ^ <
    // - TTB

    // Helper function to get all stakers
    function _getStakers() internal view returns (address[] memory) {
        return stakerSet.values();
    }

    // Really, go do something else
    // I'm just rambling at this point
    // I just finished the first draft of this contract
    // And I'm feeling a bit loopy
    // But I'm happy with how it turned out
    // And I'm excited to test it
    // - TTB 01/07/2025
}