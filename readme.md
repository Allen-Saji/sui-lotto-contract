# SuiLotto — A Multi-Winner On-Chain Lottery on Sui

## Project Overview

SuiLotto is a decentralized lottery protocol built on the Sui blockchain. Players purchase tickets by depositing SUI tokens into a shared prize pool. When the lottery deadline is reached, random winners are selected on-chain using Sui's native randomness module. The number of winners scales with participation — more players means more winners! Winners share 98% of the prize pool equally, while 2% goes to the protocol as a fee.

The lottery leverages Sui's unique features including the object-centric model for managing lottery state, shared objects for permissionless participation, and native VRF (Verifiable Random Function) for provably fair winner selection.

---

## Rules

### Basic Mechanics

1. An admin creates a lottery round by setting a ticket price and deadline
2. Players buy tickets by paying the exact ticket price in SUI — each payment equals one ticket
3. Players can buy unlimited tickets to increase their winning odds
4. At least 2 participants are required for a valid draw
5. After the deadline, the admin triggers the draw
6. Winners are randomly selected — probability proportional to tickets held
7. Winners share 98% of the prize pool equally, 2% goes to protocol

### Winner Tiers

The number of winners scales with ticket count:

| Tickets Sold | Winners | Prize per Winner (of 98%) |
| ------------ | ------- | ------------------------- |
| 2-5          | 1       | 100%                      |
| 6-9          | 2       | 50% each                  |
| 10-99        | 3       | ~33.3% each               |
| 100+         | 5       | 20% each                  |

**Note:** Same address CAN win multiple times if they hold multiple tickets. Each ticket is a separate entry in the draw.

### Roles

| Role   | Permissions                                         |
| ------ | --------------------------------------------------- |
| Admin  | Create lottery rounds, trigger draws after deadline |
| Player | Purchase tickets while lottery is active            |

### Prize Distribution

| Recipient        | Share |
| ---------------- | ----- |
| Winners          | 98%   |
| Protocol (Admin) | 2%    |

### Lottery States

| State     | Description                                           |
| --------- | ----------------------------------------------------- |
| Active    | Accepting ticket purchases, deadline not yet reached  |
| Completed | Winners selected, funds distributed                   |

### Constraints

- **Minimum Players**: 2 participants required for a valid draw
- **Deadline**: Set upfront at lottery creation, enforced on-chain
- **Refunds**: Available if deadline passes with fewer than 2 participants

### Randomness

Winner selection uses Sui's native `sui::random` module, providing verifiable on-chain randomness that cannot be manipulated by any party including the admin. The `draw_winner` function is marked as `entry` (not `public`) to prevent composition attacks on the randomness.

---

## Architecture

### Objects

#### AdminCap

| Property     | Value                                       |
| ------------ | ------------------------------------------- |
| Type         | Owned object                                |
| Purpose      | Capability token granting admin permissions |
| Created      | Once on contract deployment                 |
| Transferable | Yes                                         |

**Fields:**

- `id`: UID — unique object identifier

---

#### Lottery

| Property      | Value                              |
| ------------- | ---------------------------------- |
| Type          | Shared object                      |
| Purpose       | Holds lottery state and prize pool |
| Created       | By admin via `create_lottery`      |
| Accessible By | Anyone                             |

**Fields:**

| Field           | Type              | Description                                                      |
| --------------- | ----------------- | ---------------------------------------------------------------- |
| `id`            | UID               | Unique object identifier                                         |
| `ticket_price`  | u64               | Price per ticket in MIST (1 SUI = 1,000,000,000 MIST)            |
| `balance`       | Balance\<SUI\>    | Accumulated prize pool                                           |
| `participants`  | vector\<address\> | List of ticket holders (duplicates allowed for multiple tickets) |
| `deadline`      | u64               | Epoch timestamp (ms) when lottery ends                           |
| `status`        | u8                | 0 = Active, 1 = Completed                                        |
| `winners`       | vector\<address\> | Winner addresses, set after draw                                 |
| `admin_fee_bps` | u16               | Admin fee in basis points (200 = 2%)                             |

---

### Functions

#### Admin Functions

| Function         | Parameters                              | Description                           | Access Control     |
| ---------------- | --------------------------------------- | ------------------------------------- | ------------------ |
| `init`           | —                                       | Creates AdminCap on deployment        | System (automatic) |
| `create_lottery` | admin_cap, ticket_price, deadline, clock | Creates new lottery round            | AdminCap holder    |
| `draw_winner`    | lottery, admin_cap, random, clock       | Selects winners and distributes funds | AdminCap holder    |

#### Player Functions

| Function       | Parameters             | Description                                     | Access Control    |
| -------------- | ---------------------- | ----------------------------------------------- | ----------------- |
| `buy_ticket`   | lottery, payment, clock | Purchase ticket(s) with SUI                    | Anyone            |
| `claim_refund` | lottery, clock         | Claim refund if < 2 participants after deadline | Participants only |

#### View Functions

| Function                   | Returns         | Description                                   |
| -------------------------- | --------------- | --------------------------------------------- |
| `get_pool_size`            | u64             | Current prize pool balance                    |
| `get_participant_count`    | u64             | Number of tickets sold                        |
| `get_deadline`             | u64             | Lottery end timestamp                         |
| `get_ticket_price`         | u64             | Price per ticket                              |
| `get_winners`              | vector\<address\> | Winner addresses (after draw)               |
| `get_status`               | u8              | Lottery status (0=Active, 1=Completed)        |
| `get_expected_winner_count`| u8              | Number of winners for given participant count |
| `is_active`                | bool            | Whether lottery is still accepting tickets    |

---

### Events

| Event                | Trigger             | Fields                                                    |
| -------------------- | ------------------- | --------------------------------------------------------- |
| `LotteryCreatedEvent`  | New lottery created | lottery_id, ticket_price, deadline                        |
| `TicketPurchasedEvent` | Ticket bought       | lottery_id, buyer, tickets_bought, total_pool             |
| `WinnersSelectedEvent` | Draw completed      | lottery_id, winners, prize_per_winner, total_prize, admin_fee |
| `RefundClaimedEvent`   | Refund processed    | lottery_id, claimant, amount                              |

---

### Flow Diagram

```
                              DEPLOYMENT
                                  │
                                  ▼
                        ┌─────────────────┐
                        │  init() called  │
                        │ AdminCap created│
                        └────────┬────────┘
                                 │
                                 ▼
                          LOTTERY CREATION
                                 │
            Admin calls create_lottery(price, deadline)
                                 │
                                 ▼
                        ┌─────────────────┐
                        │ Lottery object  │
                        │ (Shared, Active)│
                        └────────┬────────┘
                                 │
                                 ▼
                      TICKET PURCHASE PHASE
                                 │
       ┌──────────┐  buy_ticket()  ┌──────────────────┐
       │  Player  │ ──────────────▶│     Lottery      │
       └──────────┘  (sends SUI)   │ - adds to pool   │
                                   │ - records address│
       ┌──────────┐  buy_ticket()  │   in participants│
       │  Player  │ ──────────────▶│                  │
       └──────────┘                └──────────────────┘
                                 │
               (continues until deadline reached)
                                 │
                                 ▼
                         DEADLINE REACHED
                                 │
                 ┌───────────────┴───────────────┐
                 │                               │
                 ▼                               ▼
        ≥ 2 participants               < 2 participants
                 │                               │
                 ▼                               ▼
    ┌────────────────────┐          ┌────────────────────┐
    │ Admin calls        │          │ Players call       │
    │ draw_winner()      │          │ claim_refund()     │
    └─────────┬──────────┘          └────────────────────┘
              │
              ▼
    ┌─────────────────────┐
    │ Determine # winners │
    │ based on tickets:   │
    │ 2-5→1, 6-9→2,       │
    │ 10-99→3, 100+→5     │
    └─────────┬───────────┘
              │
              ▼
    ┌─────────────────┐
    │ sui::random     │
    │ selects winners │
    └────────┬────────┘
              │
              ▼
    ┌─────────────────────────────────┐
    │                                 │
    ▼                                 ▼
┌────────────────────┐       ┌──────────────┐
│ 98% ÷ N → Winners  │       │ 2% → Admin   │
│ (split equally)    │       │              │
└────────────────────┘       └──────────────┘
              │
              ▼
    Lottery status → Completed
```

---

### Error Codes

| Code | Constant                   | Triggered When                                       |
| ---- | -------------------------- | ---------------------------------------------------- |
| 0    | `ELotteryNotActive`        | Buying ticket after deadline or on completed lottery |
| 1    | `EDeadlineNotReached`      | Attempting to draw before deadline                   |
| 2    | `EInvalidTicketPrice`      | Payment amount doesn't match ticket price            |
| 3    | `ENotEnoughParticipants`   | Drawing with fewer than 2 players                    |
| 4    | `ELotteryAlreadyCompleted` | Drawing on already-completed lottery                 |
| 5    | `ERefundNotAvailable`      | Claiming refund when not eligible                    |
| 6    | `ENotAParticipant`         | Non-participant attempting to claim refund           |
| 7    | `EDeadlinePassed`          | Buying ticket after deadline passed                  |
| 8    | `EInvalidDeadline`         | Creating lottery with deadline in the past           |

---

### Security Considerations

| Concern              | Mitigation                                                       |
| -------------------- | ---------------------------------------------------------------- |
| Random manipulation  | Using Sui's native `sui::random` VRF — cryptographically secure  |
| Composition attacks  | `draw_winner` is `entry` only, preventing wrapper exploits       |
| Unauthorized draw    | Only AdminCap holder can trigger draw                            |
| Early draw           | Deadline enforced on-chain via Clock, cannot draw before         |
| Fund safety          | Funds held in Lottery object, released only via draw or refund   |
| Reentrancy           | Move's linear type system prevents reentrancy by design          |
| Front-running        | Randomness revealed only during draw execution                   |

---

### Tech Stack

| Component      | Technology         |
| -------------- | ------------------ |
| Smart Contract | Move (Sui Move)    |
| Blockchain     | Sui Testnet        |
| Randomness     | sui::random        |
| Frontend       | React + TypeScript |
| Sui SDK        | @mysten/sui        |
| Wallet         | Sui Wallet / Suiet |

---

### File Structure

```
sui_lotto/
├── Move.toml                 # Package manifest
├── sources/
│   └── lottery.move          # Main contract
├── tests/
│   └── lottery_tests.move    # Unit tests (19 tests)
└── readme.md                 # This file
```

---

### Quick Start

```bash
# Build the contract
sui move build

# Run tests
sui move test

# Deploy to testnet
sui client publish --gas-budget 100000000
```
