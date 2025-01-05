# TimeTickBase Staking System Specification

## Overview

The TimeTickBase (TTB) staking system implements a proportional reward distribution mechanism based on stake-hours. This system maintains the philosophical foundation of time-based tokens while providing an efficient and mathematically sound reward distribution method.

## Core Concepts

### Renewal Requirement
- Stakes must be renewed every 6 months
- Serves as proof-of-life mechanism
- Prevents indefinite reward accumulation by abandoned stakes
- No penalty for renewal beyond timeframe
- Non-renewed stakes are automatically returned
- Accumulated rewards remain claimable

### Stake Units
- Basic unit is one stake (3,600 TTB)
- Represents potential claim on one hour of token generation
- Stakes must be complete units
- Stakes only count after one full hour of existence

### Stake-Hours
- Unit of accumulated reward credit
- Calculated hourly as: (user_stakes / total_network_stakes)
- Accumulates fractionally over time
- One completed stake-hour = 3,600 TTB in rewards
- Tracks proportional network participation over time

### Unstaking Delay
- Fixed delay period between unstaking request and token return
- Typically several days
- Prevents rapid stake cycling and emotional responses to market events
- Natural protection against coordinated unstaking attacks
- All unstaking requests process in FIFO order
- Does not affect reward accumulation during delay period

## Technical Implementation

### Core Contract State Storage

```solidity
struct UnstakeRequest {
    uint256 amount;         // Amount requested to unstake
    uint256 requestTime;    // When request was made
    uint256 processTime;    // When request can be processed
    bool pending;          // Whether there's an active request
}

struct Staker {
    uint256 currentStakes;           // Current stake units
    uint256 stakedHourAccumulator;   // Accumulated stake-hours
    uint256 lastProcessedHour;       // Last hour accumulator was updated
    uint256 lastRenewalTimestamp;    // Last time stake was renewed
    UnstakeRequest unstakeRequest;   // Single active unstake request
}

mapping(address => Staker) public stakers;
uint256 public networkTotalStakes;   // Total valid stakes in network
uint256 public constant UNSTAKE_DELAY = 3 days;
```

Note: Renewal preferences and notifications are handled by a separate management contract to maintain core contract immutability.

### Core Operations

#### Stake Deposit
1. Validate stake amount (multiple of 3,600 TTB)
2. Queue stake addition for next hour boundary
3. Stake processed at next hour boundary
4. networkTotalStakes updated when change processes

#### Stake Withdrawal Request

1. Validate stake existence and amount
2. Create unstake request with:
   - Current timestamp
   - Process time (current + UNSTAKE_DELAY)
   - Requested amount
3. Add to unstake queue
4. Emit UnstakeRequestedEvent

#### Process Unstaking
1. Check for mature unstake requests (processTime <= current time)
2. Queue stake removal for next hour boundary
3. Process at next hour boundary, updating networkTotalStakes
4. Transfer TTB after hour boundary
5. Remove request from queue

#### Hourly Processing
1. Process any pending stake changes
2. Update networkTotalStakes
3. For each staker with valid stakes:
   - Calculate proportion: stakes / networkTotalStakes
   - Add proportion to stakedHourAccumulator
   - Update lastProcessedHour

#### Reward Claims
1. Process any pending hours
2. Calculate rewards: stakedHourAccumulator * 3600
3. Zero out stakedHourAccumulator
4. Transfer TTB tokens

### Renewal System

#### Core Mechanics
- 6-month renewal requirement for all stakes
- Renewal is proof-of-life mechanism
- No penalty for renewal beyond required timeframe
- Automatic stake return if renewal missed

#### Stake Return Process
If lastRenewalTimestamp + 6 months < current_time:
1. Transfer full stake amount back to user (currentStakes * 3600 TTB)
2. Accumulated rewards remain claimable
3. Set currentStakes to 0
4. Emit StakeReturnedEvent

#### Renewal Management
- Handled by separate management contract
- Can implement automated renewal systems
- Manages user preferences and notifications
- Upgradeable without affecting core staking mechanics

## Example Scenarios

### Basic Staking
Starting State:
- Network: 10,000 total stakes
- Alice: 1,000 stakes
- Bob: 2,000 stakes
- Charlie: 7,000 stakes

Hour 1:
- Alice accumulates: 1000/10000 = 0.1 stake-hours
- Bob accumulates: 2000/10000 = 0.2 stake-hours
- Charlie accumulates: 7000/10000 = 0.7 stake-hours

Hour 2:
- Same distribution
- Alice total: 0.2 stake-hours
- Bob total: 0.4 stake-hours
- Charlie total: 1.4 stake-hours

Hour 3 (Bob adds 1,000 stakes):
- Network total: 11,000 stakes
- Alice accumulates: 1000/11000 ≈ 0.0909 stake-hours (total 0.2909)
- Bob accumulates: 3000/11000 ≈ 0.2727 stake-hours (total 0.6727)
- Charlie accumulates: 7000/11000 ≈ 0.6363 stake-hours (total 2.0363)

If they claim now:
- Alice receives: 0.2909 * 3600 = 1,047.24 TTB
- Bob receives: 0.6727 * 3600 = 2,421.72 TTB
- Charlie receives: 2.0363 * 3600 = 7,330.68 TTB

### Unstaking Example
1. Bob requests to unstake 1,000 stakes at T
2. Request queued with processTime = T + 3 days
3. Stake continues accumulating rewards normally
4. At T + 3 days, unstake processes after hour evaluation
5. Bob's stake reduces by 1,000 at next hour boundary

## Security Considerations

### Precision Handling
- All calculations must handle decimal precision appropriately
- Accumulator should use fixed-point arithmetic
- Rounding should always favor the protocol

### State Management
- Clear stake change queuing system
- Atomic operations for stake changes
- Proper overflow protection
- Gas optimization for batch processing

### Unstaking Protection
- Fixed delay provides market stability
- FIFO processing prevents gaming
- Continued rewards during delay maintain fairness
- Clear unstake status tracking

### Stake Renewal System
- Renewal required every 6 months
- User-initiated confirmation of stake maintenance
- Automatic unstaking if not renewed
- Early renewal allowed
- Clear warning system as deadline approaches
### Risk Mitigations
- Maximum stake limit to prevent manipulation
- Rate limiting on stake changes
- Emergency pause capabilities
- Proper access controls
- Automated stake return on missed renewal
## Interface Requirements

### Smart Contract
- Clear view functions for stake status
- Efficient batch processing
- Event emission for all state changes
- Proper error handling and revert messages
- Unstake queue inspection functions

### Dapp Interface
- Display current stakes
- Show accumulated stake-hours
- Estimate current rewards
- Track pending stake changes
- Display unstaking requests and status
- Show network total stakes
- Historical stake tracking

## Future Considerations

### Scalability
- System naturally handles large user bases efficiently
- Only stores state changes in networkStakesByHour
- Low per-user storage requirements
- Efficient batch processing of rewards

### Features
- Automated compounding through management contracts
- Delegation mechanisms
- Team staking integration
- Analytics and reporting

This specification provides the foundation for implementing the TTB staking system while maintaining flexibility for future improvements and optimizations. The core contract remains immutable while allowing extension through separate management contracts.

Note: Need to handle math precision, rounding, remainder, etc