# TimeTickBase Staking System Specification

## Overview

The TimeTickBase (TTB) staking system implements a proportional reward distribution mechanism based on stake-hours. This system maintains the philosophical foundation of time-based tokens while providing an efficient and mathematically sound reward distribution method.

## Core Concepts

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

## Technical Implementation

### State Storage

```solidity
struct Staker {
    uint256 currentStakes;           // Current stake units
    uint256 stakedHourAccumulator;   // Accumulated stake-hours
    uint256 nextChangeHour;          // When stake changes take effect
    uint256 lastProcessedHour;       // Last hour accumulator was updated
    uint256 lastRenewalTimestamp;    // Last time stake was renewed
    bool autoRenewalEnabled;         // Optional: Allow automatic renewal
}

mapping(address => Staker) public stakers;
mapping(uint256 => uint256) public networkStakesByHour;
```

### Core Operations

#### Stake Deposit
1. Validate stake amount (multiple of 3,600 TTB)
2. Queue stake addition for next hour
3. Update networkStakesByHour for next hour
4. Set nextChangeHour

#### Stake Withdrawal
1. Validate stake existence
2. Queue stake removal for next hour
3. Update networkStakesByHour for next hour
4. Set nextChangeHour

#### Hourly Processing
1. For each staker with valid stakes:
   - Calculate proportion: stakes / total_network_stakes
   - Add proportion to stakedHourAccumulator
   - Update lastProcessedHour

#### Reward Claims
1. Process any pending hours
2. Calculate rewards: stakedHourAccumulator * 3600
3. Zero out stakedHourAccumulator
4. Transfer TTB tokens

## Example Scenario

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

### Dapp Interface
- Display current stakes
- Show accumulated stake-hours
- Estimate current rewards
- Track pending stake changes
- Show network total stakes
- Historical stake tracking

## Future Considerations

### Scalability
- Batch processing optimization
- State compression techniques
- Gas optimization strategies

### Features
- Automated compounding
- Delegation mechanisms
- Team staking integration
- Analytics and reporting

This specification provides the foundation for implementing the TTB staking system while maintaining flexibility for future improvements and optimizations.

Note: Need to handle math precision, rounding, remainder, etc