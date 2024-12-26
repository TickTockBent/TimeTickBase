# TimeTickBase (TTB) Tokenomics
*Version 2.0 – December 2024*

## Token Generation
- Fixed emission rate of 1 TTB per second
- Batched hourly distributions (~3,600 TTB per batch)
- Supply increases linearly with time
- No pre-mine or initial allocation
- Supply validation through block timestamps
- Overflow protection and precision handling implemented

## Distribution Model

### Without Active Stakers
- Development Fund: 100% of emissions

### With Active Stakers
- Stakers: 70% of emissions
- Development Fund: 30% of emissions

## Staking Mechanism

### Individual Staking
- Minimum stake: Determined by global variable, expressed in atomic unit (stake-hours)
- Base unit: 3,600 TTB (one stake-hour)
- Rewards proportional to maintained stake
- Timelock period on withdrawals

### Team Staking
1. On-ramp Aggregator
   - Counts as a single share (one stake-hour)
   - No member stake requirement
   - Initial distribution mechanism

2. Full-stake Aggregator
   - Pooled stake structure
   - Members transfer stake to leader on join
   - Stake returned to member on exit
   - Reward distribution configured by contract structure

## Genesis Fountain

### Structure
- Duration: 12 months from launch
- Fixed 50 slots
- Initial 70% network emissions
- Natural dilution as stakers join

### Slot Distribution
- Community Development: 10 slots
- Social Engagement: 10 slots
- Random Selection: 10 slots
- Development Reserve: 10 slots
- Development Funding: 10 slots

## Development Fund

### Governance
- Multi-signature (3-of-5) requirement
- 24-hour timelock on withdrawals
- Maximum withdrawal limits
- Quarterly public reporting

### Usage
- Development costs
- Security audits
- Network infrastructure
- Staff compensation
- User acquisition
- System maintenance