# Automated Royalty Splitting Contract

## Overview

The Automated Royalty Splitting Contract is a Clarity smart contract designed for the Stacks blockchain that enables automatic distribution of royalties among multiple recipients. This contract allows content creators, artists, and other stakeholders to set up transparent and immutable royalty distribution schemes.

## Features

- **Multi-recipient Splits**: Support for up to 20 recipients per royalty split
- **Percentage-based Distribution**: Flexible percentage allocation using basis points (0.01% precision)
- **Automated Payments**: Direct STX transfers to recipient wallets
- **Access Control**: Owner-based permissions for split management
- **Emergency Controls**: Pause/unpause functionality and emergency withdrawal
- **Payment Tracking**: Complete audit trail of all royalty distributions
- **User Management**: Track splits associated with each user

## Contract Constants

- **Maximum Recipients**: 20 per split
- **Percentage Precision**: 10,000 basis points (100.00%)
- **Minimum Split Amount**: 1,000,000 micro-STX (1 STX)

## Data Structures

### Royalty Splits
Each royalty split contains:
- `owner`: Principal who created and manages the split
- `name`: Human-readable identifier (max 50 ASCII characters)
- `total-percentage`: Sum of all recipient percentages
- `active`: Whether the split is currently operational
- `created-at`: Block height when the split was created

### Split Recipients
Each recipient in a split has:
- `percentage`: Their share in basis points
- `total-received`: Total amount received to date
- `active`: Whether they are eligible for distributions

## Public Functions

### create-royalty-split
Creates a new royalty split configuration.

**Parameters:**
- `name`: String identifier for the split
- `recipients`: List of recipient data with principal addresses and percentages

**Returns:** Split ID on success

**Requirements:**
- Contract must not be paused
- Recipients list cannot be empty
- Total percentage cannot exceed 100%
- No duplicate recipients allowed

### distribute-royalties
Distributes the contract's STX balance to recipients of a specific split.

**Parameters:**
- `split-id`: ID of the split to distribute

**Requirements:**
- Contract must not be paused
- Split must be active
- Contract balance must meet minimum threshold

### deposit-royalties
Deposits STX into the contract for future distribution.

**Parameters:**
- `split-id`: ID of the target split
- `amount`: Amount to deposit in micro-STX

### update-recipient
Updates a recipient's percentage in an existing split.

**Parameters:**
- `split-id`: ID of the split
- `recipient`: Principal address to update
- `new-percentage`: New percentage in basis points

**Requirements:**
- Must be called by split owner
- Split must be active
- New percentage must be valid (1-10000 basis points)

### deactivate-split
Deactivates a royalty split, preventing further distributions.

**Parameters:**
- `split-id`: ID of the split to deactivate

**Requirements:**
- Must be called by split owner

## Administrative Functions

### emergency-pause
Pauses all contract operations (owner only).

### emergency-unpause
Resumes contract operations (owner only).

### emergency-withdraw
Allows owner to withdraw funds when contract is paused.

**Parameters:**
- `amount`: Amount to withdraw in micro-STX

## Read-Only Functions

### get-royalty-split
Retrieves split configuration by ID.

### get-recipient-info
Gets recipient details for a specific split.

### get-user-splits
Returns all split IDs associated with a user.

### get-next-split-id
Returns the next available split ID.

### is-contract-paused
Checks if contract operations are paused.

### calculate-split-amount
Calculates the distribution amount for a given percentage.

## Error Codes

- `u1001`: Unauthorized access
- `u1002`: Invalid recipient
- `u1003`: Invalid percentage
- `u1004`: Insufficient balance
- `u1005`: Already exists
- `u1006`: Not found
- `u1007`: Invalid amount
- `u1008`: Percentage overflow
- `u1009`: Empty recipients list
- `u1010`: Payment failed
- `u1011`: Invalid token contract

## Usage Example

```clarity
;; Create a royalty split with three recipients
(contract-call? .royalty-contract create-royalty-split
  "My Music Royalties"
  (list
    { recipient: 'SP1ABC..., percentage: u5000 }    ;; 50%
    { recipient: 'SP2DEF..., percentage: u3000 }    ;; 30%
    { recipient: 'SP3GHI..., percentage: u2000 }    ;; 20%
  )
)

;; Deposit royalties
(contract-call? .royalty-contract deposit-royalties u1 u5000000)

;; Distribute royalties
(contract-call? .royalty-contract distribute-royalties u1)
```

## Security Considerations

- Only split owners can modify their splits
- Contract owner has emergency controls
- All payments are atomic and traceable
- Percentage validation prevents over-allocation
- Minimum thresholds prevent dust transactions

## Deployment Requirements

- Stacks blockchain environment
- Sufficient STX for contract deployment
- Clarity version compatibility