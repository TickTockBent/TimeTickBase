# TimeTickBase (TTB)
## A Time-Based Token System with Team Staking
*Version 2.0 – December 2024*

## Abstract

TimeTickBase (TTB) introduces a token system that creates a direct relationship between time and token generation through smart contracts. By implementing a fixed emission rate of one token per second and enabling staking for both individuals or collaborativly through team structures, TTB provides a foundation for the first time-based digital asset systems on the Polygon network.

## 1. Introduction

Time is humanity's most fundamental shared resource - universally measurable yet impossible to store or trade. While blockchain technology has enabled various forms of digital scarcity, no system has successfully created a direct relationship between time itself and token generation.

TimeTickBase addresses this by implementing a token system where emission is governed by the passage of time itself - exactly one token per second, immutably encoded in smart contracts. This creates a digital asset whose supply growth perfectly mirrors the flow of time, enabled by modern blockchain technology.

By tying token generation to an immutable physical law, the linear passage of time, TTB aims to be nothing less than the most incorruptible trustless token system ever created. Ambitious? Perhaps. But an ambition worth pursuing.

## 2. System Architecture

At its core, TTB implements a token generation system that mints exactly one token per second. This emission rate is immutable - encoded in smart contracts with no ability to arbitrarily mint additional tokens or modify the generation rate. The system batches these emissions (generally hourly) for efficient distribution, with approximately 3,600 tokens distributed in each hourly batch.

The generation mechanism relies on Polygon network block timestamps for time measurement. While this creates some variance in the precise second-by-second emission, the hourly batching system includes a total time verification step which ensures the correct total supply over time. The smart contract implements careful overflow protection and precision handling to maintain accurate token counts even at large numbers.

Distribution of newly generated tokens follows two distinct patterns based on network participation. When no active stakers (called timekeepers) exist, all newly generated tokens are directed to the development fund to bootstrap the ecosystem. Once stakers join the network, 70% of new tokens are distributed proportionally among active stakers, with the remaining 30% allocated to the development fund.

## 3. Staking Mechanism

The staking system enables participants to lock TTB tokens and receive a portion of ongoing token generation. The minimum stake amount is set at 86,400 TTB - symbolically representing one day's worth of token generation. This creates a natural alignment between stake amounts and time periods. Because any stake below this amount confers no benefit, all staking is tracked in stake-days, or atomic units of 86,400 TTB.

Staking operations are managed through smart contracts that track deposits, calculate rewards, and handle withdrawals. All staked tokens are subject to a timelock period to prevent rapid withdrawal and maintain system stability. The contracts implement comprehensive safety measures including reentrancy protection, balance verification, and atomic transaction handling.

To encourage collaboration and enable larger-scale participation, TTB also implements the concept of team staking in the form of aggregator contracts. Aggregator contracts can allow multiple stakes to cooperate under a single managing address, with configurable internal reward distribution. This creates opportunities for coordinated participation while maintaining individual stake ownership.

From the start, two aggregator contract templates will be shared with the community, and TTB will implement connectors for these separate contracts to interact with.

Type 1: On-ramp Aggregator

An on-ramp aggregator effectively acts as a tap or faucet. The key difference between this aggregator contract and a full-stake aggregator is that an on-ramp contract acts as only a single stake when calculating rewards, but does not require its members to put forward any stake of their own. Deploying an on-ramp aggregator contract requires one stake-day worth of tokens staked. One of these will be activated by the dev team some time after the initial contract deployment, offering time-based membership under certain conditions. This will act as the initial token distribution mechanism, with the first on-ramp contract receiving most of the initial rewards before individual stakes begin to appear, or other teams deploy their own contracts.

Type 2: Full-stake Aggregator

A full-stake aggregator is a team/pool based structure. Such a contract will interact with the primary contract, reporting its membership. Every member of a full-stake contract must transfer one stake-day to the aggregator contract, which will collect their stake rewards on their behalf. Full-stake aggregators can then implement their own reward distribution mechanisms. This structure is intended to simplify the handling of larger groups who all wish to maintain their own stake but are not interested in or able to manage their own tokens and would like to stake as a group with other individuals.

## 4. Development Fund

The development fund plays a crucial role in ensuring sustainable system growth and maintenance. Unlike systems that rely on premines or token sales, TTB's development fund grows organically through ongoing token generation. This creates a more natural alignment between development resources and system growth.

To ensure responsible fund management while maintaining operational flexibility, the fund implements several governance mechanisms:
- Multi-signature (3-of-5) requirement for withdrawals
- 24-hour timelock on all withdrawal operations
- Maximum single withdrawal limits
- Public transaction records and quarterly reporting
- Emergency pause capability for security incidents

Fund usage focuses on core system needs: development costs, security audits, network infrastructure, staff salaries, user acquisition, and ongoing maintenance. All usage is publicly documented to maintain transparency with the community.

## 5. Technical Implementation

TTB is implemented as a set of smart contracts on the Polygon network. The core contracts handle:
1. Token generation and supply management
2. Stake deposits and withdrawals
3. Aggregator management and reward distribution
4. Development fund operations

The system leverages Polygon's efficient block times and low transaction costs to enable frequent reward distributions while maintaining reasonable gas costs for participants. All contracts undergo professional security audits and implement comprehensive safety measures including:
- SafeMath operations for all calculations
- Reentrancy guards on state-changing functions
- Precise overflow protection
- Robust access controls
- Emergency pause mechanisms

## 6. Initial Distribution Mechanism

### The Genesis Fountain

The initial token distribution leverages TTB's on-ramp aggregator system through a special implementation dubbed "The Genesis Fountain." This contract serves as the primary distribution mechanism during the network's first year, operating as a single stake-day in the system while enabling broader initial participation.

The Genesis Fountain is unique among on-ramp aggregators in three ways:
1. Limited operational period of one year from network genesis
2. Fixed membership of 50 slots
3. Receives the initial network emissions (70% of all generated tokens) until other timekeepers join

### Slot Distribution

The 50 Genesis Fountain slots are allocated through multiple channels to ensure fair and purposeful initial distribution:

* 10 slots - Community Development
  * Awarded to significant code contributors
  * Documentation and testing contributions
  * Technical community support
  
* 10 slots - Social Engagement
  * Content creation and education
  * Community building initiatives
  * Network awareness campaigns
  
* 10 slots - Random Selection
  * Public random drawing
  * Equal chance for all applicants
  * Community participation opportunity
  
* 10 slots - Development Reserve
  * Bug bounty rewards
  * Security contributions
  * Future community initiatives
  
* 10 slots - Development Funding
  * Available for purchase
  * Funds allocated to development costs
  * Smart contract audits and deployment

### Implementation Rationale

This distribution strategy serves multiple crucial purposes:

1. **Fair Access**: 80% of slots are available through merit, contribution, or random chance, ensuring broad participation opportunity.

2. **Development Funding**: The 10 purchasable slots provide essential capital for smart contract audits and deployment costs, necessary for a secure launch. These slots, like all others, offer no guaranteed tokens - only participation rights in the Genesis Fountain.

3. **Time-Limited Impact**: The one-year operational limit ensures the Genesis Fountain's influence naturally concludes, transitioning to a more distributed network as individual timekeepers join.

4. **Natural Dilution**: As individual timekeepers stake their own stake-days, the Genesis Fountain's share of rewards automatically diminishes, creating a smooth transition to broader network participation.

### Reward Mechanics

The Genesis Fountain operates as a single stake-day in the system, initially receiving 70% of all network emissions. These rewards are distributed among the 50 slot holders according to the contract's distribution logic. As additional timekeepers join the network, the Fountain's rewards naturally decrease - for example, when the first independent timekeeper stakes their stake-day, the Fountain's rewards immediately reduce to 35% of network emissions.

This mechanism ensures:
* Initial broad distribution of tokens
* Natural transition to decentralized participation
* No permanent advantages for early participants
* Gradual reduction of centralized distribution

The Genesis Fountain concludes operations exactly one year after network launch, at which point it ceases collecting rewards. This creates a clear timeline for transition to fully decentralized network participation through individual and team-based staking.

## 7. Development Roadmap

System development follows a phased approach:

Phase 1 (Q1 2025) focuses on core token mechanics: implementing the generation system, basic staking functionality, and essential security measures. This establishes the foundation for all future development.

Phase 2 (Q2 2025) introduces team staking capabilities: adding team contract deployment, member management systems, and configurable reward distribution. This enables coordinated participation and larger-scale staking operations.

Phase 3 (Q3 2025) emphasizes system optimization: improving performance, reducing gas costs, and enhancing state management. This ensures long-term system sustainability and efficiency.
