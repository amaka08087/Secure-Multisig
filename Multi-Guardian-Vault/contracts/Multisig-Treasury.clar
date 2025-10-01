;; Multi-Signature Treasury Governance Smart Contract
;; 
;; A decentralized treasury management system implementing multi-signature governance
;; with proposal-based fund disbursement, guardian-based voting, timelock mechanisms,
;; emergency controls, and comprehensive spending limits to ensure secure collaborative
;; financial decision-making for DAOs and organizations.

;; Error codes for contract operations
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-INVALID-PARAMETER (err u101))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u102))
(define-constant ERR-PROPOSAL-EXECUTED (err u103))
(define-constant ERR-PROPOSAL-CANCELLED (err u104))
(define-constant ERR-PROPOSAL-EXPIRED (err u105))
(define-constant ERR-INSUFFICIENT-BALANCE (err u106))
(define-constant ERR-THRESHOLD-EXCEEDED (err u107))
(define-constant ERR-GUARDIAN-EXISTS (err u108))
(define-constant ERR-GUARDIAN-NOT-FOUND (err u109))
(define-constant ERR-DUPLICATE-VOTE (err u110))
(define-constant ERR-VOTE-NOT-FOUND (err u111))
(define-constant ERR-INVALID-MEMO (err u112))
(define-constant ERR-TIMELOCK-ACTIVE (err u113))
(define-constant ERR-EMERGENCY-ACTIVE (err u114))
(define-constant ERR-SPENDING-LIMIT-REACHED (err u115))

;; Contract configuration constants
(define-constant default-guardian-spending-limit u1000000000)
(define-constant burn-address 'SP000000000000000000002Q6VF78)
(define-constant standard-guardian-role "standard")
(define-constant transfer-operation "transfer")
(define-constant add-guardian-operation "add-guardian")
(define-constant threshold-change-operation "threshold-change")
(define-constant max-memo-length u256)
(define-constant min-memo-length u1)
(define-constant default-proposal-validity u1008)
(define-constant max-block-duration u52560)
(define-constant blocks-per-day u144)

;; State variables tracking system configuration
(define-data-var next-proposal-id uint u0)
(define-data-var active-guardian-count uint u0)
(define-data-var approval-threshold uint u0)
(define-data-var emergency-mode-active bool false)
(define-data-var emergency-admin principal burn-address)
(define-data-var timelock-duration uint u144)
(define-data-var daily-spending-limit uint u1000000000)
(define-data-var daily-spending-total uint u0)
(define-data-var spending-reset-day uint u0)

;; Map storing all treasury proposals with their complete state
(define-map proposals
  { id: uint }
  {
    creator: principal,
    recipient: principal,
    amount: uint,
    memo: (optional (buff 256)),
    operation: (string-ascii 20),
    executed: bool,
    cancelled: bool,
    votes: uint,
    expires-at: uint,
    timelock-until: uint,
    created-at: uint
  }
)

;; Map tracking authorized guardians and their permissions
(define-map guardians
  { address: principal }
  { 
    is-active: bool,
    role: (string-ascii 15),
    spending-limit: uint,
    joined-at: uint
  }
)

;; Map recording individual guardian votes on proposals
(define-map votes
  { proposal-id: uint, guardian: principal }
  { 
    approved: bool,
    voted-at: uint
  }
)

;; Map managing vote delegation relationships
(define-map delegations
  { delegator: principal }
  {
    delegatee: principal,
    expires-at: uint
  }
)

;; Validates that a principal is not the burn address
(define-private (is-valid-principal (address principal))
  (not (is-eq address burn-address)))

;; Validates memo format meets length requirements
(define-private (is-valid-memo (memo (optional (buff 256))))
  (match memo
    content (and (>= (len content) min-memo-length) (<= (len content) max-memo-length))
    true))

;; Checks if proposal ID exists in the system
(define-private (proposal-exists (id uint))
  (< id (var-get next-proposal-id)))

;; Validates block duration is within acceptable range
(define-private (is-valid-duration (duration uint))
  (and (> duration u0) (<= duration max-block-duration)))

;; Initializes the treasury system with founding guardians and settings
(define-public (initialize-treasury (founding-guardians (list 20 principal)) 
                                    (required-votes uint)
                                    (emergency-controller principal))
  (begin
    (asserts! (is-eq (var-get active-guardian-count) u0) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (<= required-votes (len founding-guardians)) ERR-THRESHOLD-EXCEEDED)
    (asserts! (> required-votes u0) ERR-INVALID-PARAMETER)
    (asserts! (is-valid-principal emergency-controller) ERR-INVALID-PARAMETER)
    (asserts! (is-eq (len (filter is-valid-principal founding-guardians)) (len founding-guardians)) ERR-INVALID-PARAMETER)
    (var-set approval-threshold required-votes)
    (var-set emergency-admin emergency-controller)
    (map register-founding-guardian founding-guardians)
    (ok true)))

;; Registers a founding guardian during initialization
(define-private (register-founding-guardian (address principal))
  (begin
    (map-set guardians 
      { address: address } 
      { is-active: true, role: standard-guardian-role, 
        spending-limit: default-guardian-spending-limit, joined-at: block-height })
    (var-set active-guardian-count (+ (var-get active-guardian-count) u1))
    true))

;; Creates a new fund transfer proposal
(define-public (create-transfer-proposal (recipient principal) 
                                         (amount uint) 
                                         (memo (optional (buff 256))) 
                                         (valid-for uint))
  (let ((proposal-id (var-get next-proposal-id))
        (guardian-data (unwrap! (map-get? guardians { address: tx-sender }) ERR-UNAUTHORIZED-ACCESS)))
    (asserts! (is-valid-principal recipient) ERR-INVALID-PARAMETER)
    (asserts! (is-valid-memo memo) ERR-INVALID-MEMO)
    (asserts! (is-valid-duration valid-for) ERR-INVALID-PARAMETER)
    (asserts! (get is-active guardian-data) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (var-get emergency-mode-active)) ERR-EMERGENCY-ACTIVE)
    (asserts! (> amount u0) ERR-INVALID-PARAMETER)
    (asserts! (<= amount (stx-get-balance (as-contract tx-sender))) ERR-INSUFFICIENT-BALANCE)
    (asserts! (<= amount (get spending-limit guardian-data)) ERR-SPENDING-LIMIT-REACHED)
    (update-daily-spending amount)
    (asserts! (<= (var-get daily-spending-total) (var-get daily-spending-limit)) ERR-SPENDING-LIMIT-REACHED)
    (map-set proposals
      { id: proposal-id }
      {
        creator: tx-sender,
        recipient: recipient,
        amount: amount,
        memo: memo,
        operation: transfer-operation,
        executed: false,
        cancelled: false,
        votes: u1,
        expires-at: (+ block-height valid-for),
        timelock-until: (+ block-height (var-get timelock-duration)),
        created-at: block-height
      })
    (map-set votes
      { proposal-id: proposal-id, guardian: tx-sender }
      { approved: true, voted-at: block-height })
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)))

;; Allows guardians to vote on proposals
(define-public (vote-on-proposal (proposal-id uint))
  (begin
    (asserts! (proposal-exists proposal-id) ERR-PROPOSAL-NOT-FOUND)
    (asserts! (is-guardian tx-sender) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-some (map-get? proposals { id: proposal-id })) ERR-PROPOSAL-NOT-FOUND)
    (match (map-get? proposals { id: proposal-id })
      proposal-data
        (begin
          (asserts! (not (get executed proposal-data)) ERR-PROPOSAL-EXECUTED)
          (asserts! (not (get cancelled proposal-data)) ERR-PROPOSAL-CANCELLED)
          (asserts! (<= block-height (get expires-at proposal-data)) ERR-PROPOSAL-EXPIRED)
          (asserts! (not (has-voted proposal-id tx-sender)) ERR-DUPLICATE-VOTE)
          (map-set votes
            { proposal-id: proposal-id, guardian: tx-sender }
            { approved: true, voted-at: block-height })
          (map-set proposals
            { id: proposal-id }
            (merge proposal-data 
              { votes: (+ (get votes proposal-data) u1) }))
          (if (>= (+ (get votes proposal-data) u1) (var-get approval-threshold))
            (begin
              (try! (execute-proposal proposal-id))
              (ok proposal-id))
            (ok proposal-id)))
      ERR-PROPOSAL-NOT-FOUND)))

;; Executes an approved proposal after timelock expires
(define-public (execute-proposal (proposal-id uint))
  (begin
    (asserts! (proposal-exists proposal-id) ERR-PROPOSAL-NOT-FOUND)
    (asserts! (is-some (map-get? proposals { id: proposal-id })) ERR-PROPOSAL-NOT-FOUND)
    (match (map-get? proposals { id: proposal-id })
      proposal-data
        (begin
          (asserts! (not (get executed proposal-data)) ERR-PROPOSAL-EXECUTED)
          (asserts! (not (get cancelled proposal-data)) ERR-PROPOSAL-CANCELLED)
          (asserts! (<= block-height (get expires-at proposal-data)) ERR-PROPOSAL-EXPIRED)
          (asserts! (>= block-height (get timelock-until proposal-data)) ERR-TIMELOCK-ACTIVE)
          (asserts! (>= (get votes proposal-data) (var-get approval-threshold)) ERR-UNAUTHORIZED-ACCESS)
          (map-set proposals
            { id: proposal-id }
            (merge proposal-data { executed: true }))
          (if (is-eq (get operation proposal-data) transfer-operation)
            (as-contract 
              (stx-transfer? (get amount proposal-data) 
                            tx-sender 
                            (get recipient proposal-data)))
            (ok true)))
      ERR-PROPOSAL-NOT-FOUND)))

;; Creates a proposal to add a new guardian
(define-public (propose-add-guardian (new-guardian principal))
  (let ((proposal-id (var-get next-proposal-id)))
    (asserts! (is-valid-principal new-guardian) ERR-INVALID-PARAMETER)
    (asserts! (is-guardian tx-sender) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (is-guardian new-guardian)) ERR-GUARDIAN-EXISTS)
    (map-set proposals
      { id: proposal-id }
      {
        creator: tx-sender,
        recipient: new-guardian,
        amount: u0,
        memo: none,
        operation: add-guardian-operation,
        executed: false,
        cancelled: false,
        votes: u1,
        expires-at: (+ block-height default-proposal-validity),
        timelock-until: (+ block-height (var-get timelock-duration)),
        created-at: block-height
      })
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)))

;; Executes an approved guardian addition proposal
(define-public (execute-add-guardian (proposal-id uint))
  (begin
    (asserts! (proposal-exists proposal-id) ERR-PROPOSAL-NOT-FOUND)
    (asserts! (is-some (map-get? proposals { id: proposal-id })) ERR-PROPOSAL-NOT-FOUND)
    (match (map-get? proposals { id: proposal-id })
      proposal-data
        (begin
          (asserts! (is-eq (get operation proposal-data) add-guardian-operation) ERR-INVALID-PARAMETER)
          (asserts! (>= (get votes proposal-data) (var-get approval-threshold)) ERR-UNAUTHORIZED-ACCESS)
          (asserts! (>= block-height (get timelock-until proposal-data)) ERR-TIMELOCK-ACTIVE)
          (map-set proposals
            { id: proposal-id }
            (merge proposal-data { executed: true }))
          (map-set guardians 
            { address: (get recipient proposal-data) } 
            { is-active: true, role: standard-guardian-role, 
              spending-limit: default-guardian-spending-limit, joined-at: block-height })
          (var-set active-guardian-count (+ (var-get active-guardian-count) u1))
          (ok proposal-id))
      ERR-PROPOSAL-NOT-FOUND)))

;; Establishes vote delegation to another guardian
(define-public (delegate-voting-power (delegatee principal) (duration uint))
  (let ((delegator-info (unwrap! (map-get? guardians { address: tx-sender }) ERR-UNAUTHORIZED-ACCESS))
        (delegatee-info (unwrap! (map-get? guardians { address: delegatee }) ERR-GUARDIAN-NOT-FOUND)))
    (asserts! (is-valid-principal delegatee) ERR-INVALID-PARAMETER)
    (asserts! (is-valid-duration duration) ERR-INVALID-PARAMETER)
    (asserts! (get is-active delegator-info) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (get is-active delegatee-info) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (is-eq tx-sender delegatee)) ERR-INVALID-PARAMETER)
    (map-set delegations
      { delegator: tx-sender }
      {
        delegatee: delegatee,
        expires-at: (+ block-height duration)
      })
    (ok true)))

;; Removes existing vote delegation
(define-public (revoke-delegation)
  (begin
    (asserts! (is-some (map-get? delegations { delegator: tx-sender })) ERR-INVALID-PARAMETER)
    (map-delete delegations { delegator: tx-sender })
    (ok true)))

;; Activates emergency mode to halt operations
(define-public (activate-emergency-mode)
  (begin
    (asserts! (is-eq tx-sender (var-get emergency-admin)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (var-get emergency-mode-active)) ERR-EMERGENCY-ACTIVE)
    (var-set emergency-mode-active true)
    (ok true)))

;; Deactivates emergency mode to resume operations
(define-public (deactivate-emergency-mode)
  (begin
    (asserts! (is-guardian tx-sender) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (var-get emergency-mode-active) ERR-INVALID-PARAMETER)
    (var-set emergency-mode-active false)
    (ok true)))

;; Accepts STX deposits into the treasury
(define-public (deposit-funds (amount uint))
  (stx-transfer? amount tx-sender (as-contract tx-sender)))

;; Creates a proposal to change the approval threshold
(define-public (propose-threshold-change (new-threshold uint))
  (let ((proposal-id (var-get next-proposal-id)))
    (asserts! (is-guardian tx-sender) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (> new-threshold u0) ERR-INVALID-PARAMETER)
    (asserts! (<= new-threshold (var-get active-guardian-count)) ERR-THRESHOLD-EXCEEDED)
    (map-set proposals
      { id: proposal-id }
      {
        creator: tx-sender,
        recipient: tx-sender,
        amount: new-threshold,
        memo: none,
        operation: threshold-change-operation,
        executed: false,
        cancelled: false,
        votes: u1,
        expires-at: (+ block-height default-proposal-validity),
        timelock-until: (+ block-height (var-get timelock-duration)),
        created-at: block-height
      })
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)))

;; Executes an approved threshold change proposal
(define-public (execute-threshold-change (proposal-id uint))
  (begin
    (asserts! (proposal-exists proposal-id) ERR-PROPOSAL-NOT-FOUND)
    (match (map-get? proposals { id: proposal-id })
      proposal-data
        (begin
          (asserts! (is-eq (get operation proposal-data) threshold-change-operation) ERR-INVALID-PARAMETER)
          (asserts! (>= (get votes proposal-data) (var-get approval-threshold)) ERR-UNAUTHORIZED-ACCESS)
          (asserts! (>= block-height (get timelock-until proposal-data)) ERR-TIMELOCK-ACTIVE)
          (var-set approval-threshold (get amount proposal-data))
          (map-set proposals
            { id: proposal-id }
            (merge proposal-data { executed: true }))
          (ok proposal-id))
      ERR-PROPOSAL-NOT-FOUND)))

;; Cancels a proposal if authorized
(define-public (cancel-proposal (proposal-id uint))
  (begin
    (asserts! (proposal-exists proposal-id) ERR-PROPOSAL-NOT-FOUND)
    (match (map-get? proposals { id: proposal-id })
      proposal-data
        (begin
          (asserts! (not (get executed proposal-data)) ERR-PROPOSAL-EXECUTED)
          (asserts! (not (get cancelled proposal-data)) ERR-PROPOSAL-CANCELLED)
          (asserts! (or (is-eq (get creator proposal-data) tx-sender)
                       (>= (get votes proposal-data) (var-get approval-threshold))) ERR-UNAUTHORIZED-ACCESS)
          (map-set proposals
            { id: proposal-id }
            (merge proposal-data { cancelled: true }))
          (ok proposal-id))
      ERR-PROPOSAL-NOT-FOUND)))

;; Updates daily spending tracking with automatic reset
(define-private (update-daily-spending (amount uint))
  (let ((current-day (/ block-height blocks-per-day)))
    (if (> current-day (var-get spending-reset-day))
      (begin
        (var-set daily-spending-total amount)
        (var-set spending-reset-day current-day)
        true)
      (begin
        (var-set daily-spending-total (+ (var-get daily-spending-total) amount))
        true))))

;; Returns the current approval threshold
(define-read-only (get-approval-threshold) 
  (var-get approval-threshold))

;; Returns the total number of active guardians
(define-read-only (get-guardian-count) 
  (var-get active-guardian-count))

;; Returns the current treasury balance
(define-read-only (get-treasury-balance) 
  (stx-get-balance (as-contract tx-sender)))

;; Returns emergency mode status
(define-read-only (get-emergency-status) 
  (var-get emergency-mode-active))

;; Returns current daily spending information
(define-read-only (get-spending-status) 
  { total: (var-get daily-spending-total), limit: (var-get daily-spending-limit) })

;; Checks if an address is an active guardian
(define-read-only (is-guardian (address principal))
  (default-to false 
    (get is-active 
      (map-get? guardians { address: address }))))

;; Retrieves complete proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { id: proposal-id }))

;; Checks if a guardian has voted on a proposal
(define-read-only (has-voted (proposal-id uint) (guardian principal))
  (default-to false 
    (get approved 
      (map-get? votes 
        { proposal-id: proposal-id, guardian: guardian }))))

;; Retrieves guardian information and permissions
(define-read-only (get-guardian-info (address principal))
  (map-get? guardians { address: address }))

;; Retrieves delegation information for a guardian
(define-read-only (get-delegation-info (delegator principal))
  (map-get? delegations { delegator: delegator }))