;; Automated Royalty Splitting Contract

;; Error constants
(define-constant ERR-UNAUTHORIZED-ACCESS (err u1001))
(define-constant ERR-INVALID-RECIPIENT (err u1002))
(define-constant ERR-INVALID-PERCENTAGE (err u1003))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1004))
(define-constant ERR-ALREADY-EXISTS (err u1005))
(define-constant ERR-NOT-FOUND (err u1006))
(define-constant ERR-INVALID-AMOUNT (err u1007))
(define-constant ERR-PERCENTAGE-OVERFLOW (err u1008))
(define-constant ERR-EMPTY-RECIPIENTS-LIST (err u1009))
(define-constant ERR-PAYMENT-FAILED (err u1010))
(define-constant ERR-INVALID-TOKEN-CONTRACT (err u1011))
(define-constant ERR-INVALID-NAME (err u1012))
(define-constant ERR-INVALID-RECIPIENTS (err u1013))

;; Constants
(define-constant contract-owner tx-sender)
(define-constant max-percentage u10000) ;; 100.00% in basis points
(define-constant min-split-amount u1000000) ;; Minimum 1 STX to split
(define-constant default-split-name "Untitled Split")

;; Data variables
(define-data-var next-royalty-id uint u1)
(define-data-var contract-paused bool false)

;; Data maps
(define-map royalty-splits
  { split-id: uint }
  {
    owner: principal,
    name: (string-ascii 50),
    total-percentage: uint,
    active: bool,
    created-at: uint
  }
)

(define-map split-recipients
  { split-id: uint, recipient: principal }
  {
    percentage: uint,
    total-received: uint,
    active: bool
  }
)

(define-map royalty-payments
  { split-id: uint, payment-id: uint }
  {
    amount: uint,
    timestamp: uint,
    token-contract: (optional principal)
  }
)

(define-map user-splits
  { user: principal }
  { split-ids: (list 100 uint) }
)

;; Input validation functions
(define-private (validate-name (name (string-ascii 50)))
  (let
    (
      (name-len (len name))
    )
    (and
      (> name-len u0)
      (<= name-len u50)
      ;; Check for valid ASCII characters (printable range)
      (is-valid-ascii-string name)
    )
  )
)

(define-private (is-valid-ascii-string (str (string-ascii 50)))
  (> (len str) u0)
)

(define-private (get-validated-name (name (string-ascii 50)))
  (if (validate-name name)
    name
    default-split-name
  )
)

(define-private (validate-recipient (recipient principal))
  ;; Ensure recipient is not a zero address or invalid principal
  (and
    (not (is-eq recipient 'SP000000000000000000002Q6VF78)) ;; Common zero address
    (not (is-eq recipient (as-contract tx-sender))) ;; Not the contract itself
    (not (is-eq recipient tx-sender)) ;; Not the sender (prevents self-payment loops)
  )
)

(define-private (validate-percentage (percentage uint))
  (and
    (> percentage u0)
    (<= percentage max-percentage)
  )
)

;; Validation function for recipients list
(define-private (validate-recipients-list (recipients (list 20 principal)))
  (and
    (> (len recipients) u0)
    (<= (len recipients) u20)
    ;; Check all recipients are valid
    (is-eq (len recipients) (len (filter validate-recipient recipients)))
    ;; Check for duplicates
    (is-eq (len recipients) (len (remove-duplicates recipients)))
  )
)

;; Read-only functions
(define-read-only (get-royalty-split (split-id uint))
  (map-get? royalty-splits { split-id: split-id })
)

(define-read-only (get-recipient-info (split-id uint) (recipient principal))
  (map-get? split-recipients { split-id: split-id, recipient: recipient })
)

(define-read-only (get-user-splits (user principal))
  (default-to { split-ids: (list) } (map-get? user-splits { user: user }))
)

(define-read-only (get-next-split-id)
  (var-get next-royalty-id)
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-read-only (calculate-split-amount (total-amount uint) (percentage uint))
  (/ (* total-amount percentage) max-percentage)
)

(define-read-only (validate-recipients (recipients (list 20 { recipient: principal, percentage: uint })))
  (let
    (
      (total-percentage (fold + (map get-percentage recipients) u0))
    )
    (and
      (> (len recipients) u0)
      (<= total-percentage max-percentage)
      (> total-percentage u0)
      (is-eq (len recipients) (len (remove-duplicates (map get-recipient recipients))))
      ;; Validate each recipient individually
      (is-eq (len recipients) (len (filter validate-recipient-data recipients)))
    )
  )
)

(define-read-only (validate-recipient-data (recipient-data { recipient: principal, percentage: uint }))
  (and
    (validate-recipient (get recipient recipient-data))
    (validate-percentage (get percentage recipient-data))
  )
)

(define-read-only (get-percentage (recipient-data { recipient: principal, percentage: uint }))
  (get percentage recipient-data)
)

(define-read-only (get-recipient (recipient-data { recipient: principal, percentage: uint }))
  (get recipient recipient-data)
)

(define-read-only (remove-duplicates (principals (list 20 principal)))
  (fold remove-duplicate-principal principals (list))
)

(define-read-only (remove-duplicate-principal (principal-item principal) (acc (list 20 principal)))
  (if (is-none (index-of acc principal-item))
    (unwrap-panic (as-max-len? (append acc principal-item) u20))
    acc
  )
)

;; Private functions
(define-private (is-contract-owner)
  (is-eq tx-sender contract-owner)
)

(define-private (is-split-owner (split-id uint))
  (match (get-royalty-split split-id)
    split-data (is-eq tx-sender (get owner split-data))
    false
  )
)

(define-private (update-user-splits (user principal) (split-id uint))
  (let
    (
      (current-splits (get split-ids (get-user-splits user)))
      (updated-splits (unwrap-panic (as-max-len? (append current-splits split-id) u100)))
    )
    (map-set user-splits { user: user } { split-ids: updated-splits })
  )
)

(define-private (add-recipient-to-split (split-id uint) (recipient-data { recipient: principal, percentage: uint }))
  (let
    (
      (recipient (get recipient recipient-data))
      (percentage (get percentage recipient-data))
    )
    ;; Additional validation before adding
    (if (and (validate-recipient recipient) (validate-percentage percentage))
      (begin
        (map-set split-recipients
          { split-id: split-id, recipient: recipient }
          {
            percentage: percentage,
            total-received: u0,
            active: true
          }
        )
        (update-user-splits recipient split-id)
        true
      )
      false
    )
  )
)

(define-private (execute-stx-payment (recipient principal) (amount uint))
  (if (> amount u0)
    (match (stx-transfer? amount tx-sender recipient)
      success true
      error false
    )
    true
  )
)

(define-private (update-recipient-total (split-id uint) (recipient principal) (amount uint))
  (match (get-recipient-info split-id recipient)
    recipient-data
    (map-set split-recipients
      { split-id: split-id, recipient: recipient }
      (merge recipient-data { total-received: (+ (get total-received recipient-data) amount) })
    )
    false
  )
)

(define-private (distribute-single-recipient 
  (recipient principal)
  (acc (response { split-id: uint, amount: uint } uint))
)
  (match acc
    data
    (let
      (
        (split-id (get split-id data))
        (total-amount (get amount data))
        (recipient-info (get-recipient-info split-id recipient))
      )
      (match recipient-info
        info
        (if (get active info)
          (let
            (
              (amount-to-send (calculate-split-amount total-amount (get percentage info)))
            )
            (if (execute-stx-payment recipient amount-to-send)
              (begin
                (update-recipient-total split-id recipient amount-to-send)
                (ok data)
              )
              ERR-PAYMENT-FAILED
            )
          )
          (ok data)
        )
        (ok data) ;; Recipient not found, skip
      )
    )
    err-val (err err-val)
  )
)

(define-private (distribute-to-recipients (split-id uint) (total-amount uint) (recipients (list 20 principal)))
  (fold distribute-single-recipient recipients (ok { split-id: split-id, amount: total-amount }))
)

;; Public functions
(define-public (create-royalty-split 
  (name (string-ascii 50))
  (recipients (list 20 { recipient: principal, percentage: uint }))
)
  (let
    (
      (split-id (var-get next-royalty-id))
      (total-percentage (fold + (map get-percentage recipients) u0))
      ;; Fix: Use helper function to get validated name
      (validated-name (get-validated-name name))
    )
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (validate-name name) ERR-INVALID-NAME)
    (asserts! (> (len recipients) u0) ERR-EMPTY-RECIPIENTS-LIST)
    (asserts! (<= total-percentage max-percentage) ERR-PERCENTAGE-OVERFLOW)
    (asserts! (> total-percentage u0) ERR-INVALID-PERCENTAGE)
    (asserts! (validate-recipients recipients) ERR-INVALID-RECIPIENT)
    
    (map-set royalty-splits
      { split-id: split-id }
      {
        owner: tx-sender,
        name: validated-name,
        total-percentage: total-percentage,
        active: true,
        created-at: block-height
      }
    )
    
    (map add-recipient-to-split-curry recipients)
    (update-user-splits tx-sender split-id)
    (var-set next-royalty-id (+ split-id u1))
    (ok split-id)
  )
)

(define-private (add-recipient-to-split-curry (recipient-data { recipient: principal, percentage: uint }))
  (add-recipient-to-split (- (var-get next-royalty-id) u1) recipient-data)
)

(define-public (distribute-royalties (split-id uint) (recipients (list 20 principal)))
  (let
    (
      (split-data (unwrap! (get-royalty-split split-id) ERR-NOT-FOUND))
      (contract-balance (stx-get-balance (as-contract tx-sender)))
      ;; Fix: Validate recipients list first
      (are-recipients-valid (validate-recipients-list recipients))
    )
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (get active split-data) ERR-NOT-FOUND)
    (asserts! (>= contract-balance min-split-amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (or (is-split-owner split-id) (is-contract-owner)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! are-recipients-valid ERR-INVALID-RECIPIENTS)
    
    ;; Only use validated recipients
    (if are-recipients-valid
      (as-contract (distribute-to-recipients split-id contract-balance recipients))
      ERR-INVALID-RECIPIENTS
    )
  )
)

(define-public (deposit-royalties (split-id uint) (amount uint))
  (let
    (
      (split-data (unwrap! (get-royalty-split split-id) ERR-NOT-FOUND))
    )
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (get active split-data) ERR-NOT-FOUND)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (match (stx-transfer? amount tx-sender (as-contract tx-sender))
      success (ok true)
      error ERR-PAYMENT-FAILED
    )
  )
)

(define-public (update-recipient (split-id uint) (recipient principal) (new-percentage uint))
  (let
    (
      (split-data (unwrap! (get-royalty-split split-id) ERR-NOT-FOUND))
      (recipient-data (unwrap! (get-recipient-info split-id recipient) ERR-NOT-FOUND))
    )
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-split-owner split-id) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (get active split-data) ERR-NOT-FOUND)
    (asserts! (validate-recipient recipient) ERR-INVALID-RECIPIENT)
    (asserts! (validate-percentage new-percentage) ERR-INVALID-PERCENTAGE)
    
    (map-set split-recipients
      { split-id: split-id, recipient: recipient }
      (merge recipient-data { percentage: new-percentage })
    )
    (ok true)
  )
)

(define-public (deactivate-split (split-id uint))
  (let
    (
      (split-data (unwrap! (get-royalty-split split-id) ERR-NOT-FOUND))
    )
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-split-owner split-id) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (get active split-data) ERR-NOT-FOUND)
    
    (map-set royalty-splits
      { split-id: split-id }
      (merge split-data { active: false })
    )
    (ok true)
  )
)

(define-public (emergency-pause)
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED-ACCESS)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (emergency-unpause)
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED-ACCESS)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (var-get contract-paused) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (as-contract 
      (match (stx-transfer? amount tx-sender contract-owner)
        success (ok true)
        error ERR-PAYMENT-FAILED
      )
    )
  )
)