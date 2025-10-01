# Multi-Signature Treasury Governance Smart Contract

## Overview

A decentralized treasury management system implementing multi-signature governance with proposal-based fund disbursement, guardian-based voting, timelock mechanisms, emergency controls, and comprehensive spending limits. This contract enables secure collaborative financial decision-making for DAOs and organizations on the Stacks blockchain.

## Features

- Multi-signature approval system with configurable thresholds
- Proposal-based governance for all treasury operations
- Time-locked execution for enhanced security
- Emergency mode for critical situations
- Daily spending limits and per-guardian spending caps
- Vote delegation system
- Support for multiple operation types (transfers, guardian management, threshold changes)
- Comprehensive audit trail of all proposals and votes

## Core Components

### Governance Model

The contract implements a guardian-based governance system where:
- Multiple guardians collectively control the treasury
- Proposals require a minimum number of guardian approvals (threshold)
- All approved proposals are subject to a timelock period before execution
- Emergency controls allow for system-wide operation suspension

### Guardian System

Guardians are authorized participants who can:
- Create proposals for fund transfers and governance changes
- Vote on existing proposals
- Delegate their voting power to other guardians
- Each guardian has individual spending limits

### Proposal Types

1. **Transfer Proposals**: Move STX from the treasury to a recipient
2. **Add Guardian Proposals**: Add new guardians to the system
3. **Threshold Change Proposals**: Modify the approval threshold requirement

## Installation and Deployment

### Prerequisites

- Clarinet CLI installed
- Stacks blockchain node access
- Stacks wallet for deployment

### Deployment Steps

1. Clone the repository containing the contract
2. Review and configure initial parameters
3. Deploy using Clarinet:

```bash
clarinet deploy
```

4. Initialize the treasury with founding guardians

## Initialization

Before using the treasury, it must be initialized with the founding guardians and configuration:

```clarity
(contract-call? .treasury initialize-treasury 
  (list 'SP1... 'SP2... 'SP3...)  ;; List of guardian principals
  u2                               ;; Required approval threshold
  'SP...                          ;; Emergency admin address
)
```

### Initialization Parameters

- **founding-guardians**: List of up to 20 principal addresses (guardians)
- **required-votes**: Number of approvals needed for proposals (must be <= guardian count)
- **emergency-controller**: Principal authorized to activate emergency mode

## Usage Guide

### Creating Transfer Proposals

Guardians can create proposals to transfer STX from the treasury:

```clarity
(contract-call? .treasury create-transfer-proposal
  'SP...                    ;; Recipient address
  u1000000                 ;; Amount in microSTX
  (some 0x...)             ;; Optional memo (up to 256 bytes)
  u1008                    ;; Validity duration in blocks
)
```

### Voting on Proposals

Any active guardian can vote on an existing proposal:

```clarity
(contract-call? .treasury vote-on-proposal u0)  ;; Proposal ID
```

Once the approval threshold is reached and the timelock expires, the proposal can be executed.

### Executing Proposals

After a proposal receives sufficient votes and the timelock period passes:

```clarity
(contract-call? .treasury execute-proposal u0)  ;; Proposal ID
```

### Adding New Guardians

To add a new guardian, create a proposal:

```clarity
(contract-call? .treasury propose-add-guardian 'SP...)
```

Vote on the proposal, then execute:

```clarity
(contract-call? .treasury execute-add-guardian u0)
```

### Changing Approval Threshold

To modify the number of required approvals:

```clarity
(contract-call? .treasury propose-threshold-change u3)
```

After approval and timelock:

```clarity
(contract-call? .treasury execute-threshold-change u0)
```

### Vote Delegation

Guardians can delegate their voting power temporarily:

```clarity
(contract-call? .treasury delegate-voting-power
  'SP...    ;; Delegatee address
  u1008     ;; Duration in blocks
)
```

To revoke delegation:

```clarity
(contract-call? .treasury revoke-delegation)
```

### Emergency Controls

The designated emergency admin can halt all operations:

```clarity
(contract-call? .treasury activate-emergency-mode)
```

Any guardian can deactivate emergency mode:

```clarity
(contract-call? .treasury deactivate-emergency-mode)
```

### Depositing Funds

Anyone can deposit STX into the treasury:

```clarity
(contract-call? .treasury deposit-funds u1000000)
```

## Read-Only Functions

### Query Proposal Information

```clarity
(contract-call? .treasury get-proposal u0)
```

Returns complete proposal details including votes, status, and parameters.

### Check Guardian Status

```clarity
(contract-call? .treasury is-guardian 'SP...)
```

### Get Guardian Information

```clarity
(contract-call? .treasury get-guardian-info 'SP...)
```

Returns guardian details including role, spending limit, and join date.

### Check Vote Status

```clarity
(contract-call? .treasury has-voted u0 'SP...)
```

### Treasury Balance

```clarity
(contract-call? .treasury get-treasury-balance)
```

### Current Configuration

```clarity
(contract-call? .treasury get-approval-threshold)
(contract-call? .treasury get-guardian-count)
(contract-call? .treasury get-emergency-status)
(contract-call? .treasury get-spending-status)
```

## Security Features

### Timelock Mechanism

All proposals are subject to a configurable timelock period (default: 144 blocks, approximately 24 hours) before execution. This provides a security buffer for detecting malicious proposals.

### Spending Limits

Two-tier spending control:
1. **Per-Guardian Limit**: Each guardian has a maximum amount they can propose (default: 1,000,000,000 microSTX)
2. **Daily Treasury Limit**: Total daily spending cap for the entire treasury (default: 1,000,000,000 microSTX)

### Emergency Mode

When activated, emergency mode prevents:
- Creation of new transfer proposals
- Execution of pending operations

Emergency mode can only be activated by the designated emergency admin and deactivated by any guardian.

### Proposal Expiration

Proposals automatically expire after their validity period, preventing indefinite pending proposals.

## Error Codes

- **u100**: Unauthorized access attempt
- **u101**: Invalid parameter provided
- **u102**: Proposal not found
- **u103**: Proposal already executed
- **u104**: Proposal cancelled
- **u105**: Proposal expired
- **u106**: Insufficient treasury balance
- **u107**: Threshold exceeds guardian count
- **u108**: Guardian already exists
- **u109**: Guardian not found
- **u110**: Duplicate vote attempt
- **u111**: Vote not found
- **u112**: Invalid memo format
- **u113**: Timelock still active
- **u114**: Emergency mode active
- **u115**: Spending limit reached

## Configuration Constants

### Timeframes

- **default-proposal-validity**: 1,008 blocks (approximately 7 days)
- **timelock-duration**: 144 blocks (approximately 24 hours)
- **blocks-per-day**: 144 blocks
- **max-block-duration**: 52,560 blocks (approximately 1 year)

### Spending Limits

- **default-guardian-spending-limit**: 1,000,000,000 microSTX (1,000 STX)
- **daily-spending-limit**: 1,000,000,000 microSTX (1,000 STX)

### Memo Constraints

- **min-memo-length**: 1 byte
- **max-memo-length**: 256 bytes

## Best Practices

1. **Guardian Selection**: Choose trusted and diverse guardians to prevent collusion
2. **Threshold Setting**: Set threshold high enough for security but low enough for operational efficiency
3. **Regular Audits**: Periodically review pending proposals and guardian activity
4. **Memo Usage**: Include descriptive memos for all transfer proposals
5. **Emergency Admin**: Secure the emergency admin key with robust key management
6. **Timelock Monitoring**: Monitor proposals during timelock periods for suspicious activity
7. **Spending Limits**: Adjust limits based on treasury size and operational needs