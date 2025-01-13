# TTB Canonical Dual Wrapper Contract
## Pre-audited Infrastructure for Multi-Token Projects

The TTB Canonical Dual Wrapper provides a ready-made, security-audited solution for projects needing two interlinked tokens backed by TTB. Instead of building complex token systems from scratch, teams can deploy a pre-audited dual wrapper and focus on their unique mechanics.

## Value Proposition

### Why Use a Dual Wrapper?
- **Two Tokens, One Contract**: Launch two TTB-backed tokens with different properties
- **Flexible Minting Control**: One freely mintable token, one with restricted minting
- **Proven Security**: Benefit from thorough security audits without the cost
- **Independent Ratios**: Configure different wrap ratios for each token
- **Community Trust**: Users recognize and trust canonical implementations

### Cost Savings
Traditional multi-token development requires:
- 3-4 months development time
- $80,000+ for security audits
- Complex token relationship management
- Ongoing security monitoring for multiple contracts

With a canonical dual wrapper:
- Deploy two tokens in under an hour
- Zero audit costs
- Maintenance handled by TTB
- Security guaranteed by design

## Technical Implementation

### Core Features
- Two wrapped tokens from one TTB source
- Configurable wrap ratios for each token
- Restricted minting control for second token
- Standard ERC20 compliance
- Automatic supply management
- Clear event logging

### Deployment Steps
1. Clone the repository
2. Configure parameters:
   ```javascript
   const TOKEN_A_NAME = "First Token";
   const TOKEN_A_SYMBOL = "FIRST";
   const TOKEN_B_NAME = "Second Token";
   const TOKEN_B_SYMBOL = "SECOND";
   const RATIO_A = 1;      // 1:1 with TTB
   const RATIO_B = 1000;   // 1000:1 with TTB
   ```
3. Deploy to your network:
   ```bash
   yarn hardhat deploy --network your_network
   ```

### Integration Example
```solidity
// 1. Deploy wrapper
const wrapper = await deploy('TTBDualWrapper', {
  args: [
    TTB_ADDRESS,
    TOKEN_A_NAME,
    TOKEN_A_SYMBOL,
    TOKEN_B_NAME,
    TOKEN_B_SYMBOL,
    RATIO_A,
    RATIO_B
  ]
});

// 2. Set authorized minter for Token B
await wrapper.setAuthorizedMinter(MINTER_ADDRESS);

// 3. Wrap TTB to Token A
await ttbContract.approve(wrapper.address, amount);
await wrapper.wrapTTB(amount);
```

## User Guide

### For Projects
1. **Initial Setup**
   - Deploy dual wrapper contract
   - Configure token parameters
   - Set authorized minter
   - Add to token lists/DEXs

2. **Management**
   - Monitor wrap/unwrap events
   - Track token distribution
   - Manage minting permissions

3. **Integration**
   - Connect to your dApp
   - Implement minting logic
   - Build token utilities

### For Users
1. **Token A Operations**
   - Wrap TTB freely
   - Use in project ecosystem
   - Unwrap back to TTB anytime

2. **Token B Operations**
   - Receive from authorized minter
   - Use in project ecosystem
   - Unwrap back to TTB in whole units

## Common Use Cases

### Reward Systems
- Token A: Stake-able project token
- Token B: Reward token with controlled distribution

### Gaming
- Token A: In-game currency
- Token B: Special rewards or items

### DeFi
- Token A: Trading/liquidity token
- Token B: Governance or bonus token

## Security Considerations

### Built-in Protections
- Reentrancy guards
- Integer overflow protection
- Clear access controls
- Event logging
- Ratio enforcement
- Minting restrictions

### Audit Status
- Full security audit completed
- Known safe patterns used
- Regular security reviews
- Public verification tools

## Support & Resources

### Documentation
- Full API documentation
- Integration guides
- Example implementations
- Best practices

### Community
- Development forum
- Technical support
- Implementation examples
- Upgrade notifications

## Getting Started

1. **Quick Start**
   ```bash
   # Clone repository
   git clone https://github.com/your-repo/ttb-dual-wrapper

   # Install dependencies
   yarn install

   # Configure wrapper
   # Edit config.js with your parameters

   # Deploy
   yarn hardhat deploy --network your_network
   ```

2. **Next Steps**
   - Set up minting controls
   - Add to your frontend
   - Begin building features

3. **Support**
   - Join Discord community
   - Read documentation
   - Contact technical support

By using the TTB Canonical Dual Wrapper, you're building on proven, secure infrastructure that lets you focus on what makes your project unique. Perfect for games, reward systems, or any project needing two coordinated tokens.