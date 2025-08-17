(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-insufficient-stake (err u105))
(define-constant err-trade-expired (err u106))
(define-constant err-invalid-verification (err u107))

(define-data-var trade-id-nonce uint u0)
(define-data-var min-stake-amount uint u1000)
(define-data-var verification-window uint u1440)

(define-map trades
    uint
    {
        exporter: principal,
        importer: principal,
        verifier: (optional principal),
        goods-hash: (buff 32),
        quantity: uint,
        value: uint,
        status: (string-ascii 20),
        created-at: uint,
        verified-at: (optional uint),
        expires-at: uint,
        stake-amount: uint,
    }
)

(define-map verifiers
    principal
    {
        is-active: bool,
        reputation: uint,
        total-verifications: uint,
        successful-verifications: uint,
        stake-locked: uint,
        registered-at: uint,
    }
)

(define-map trade-documents
    {
        trade-id: uint,
        doc-type: (string-ascii 50),
    }
    {
        document-hash: (buff 32),
        uploaded-by: principal,
        uploaded-at: uint,
        verified: bool,
    }
)

(define-map user-stakes
    {
        user: principal,
        trade-id: uint,
    }
    {
        amount: uint,
        locked-at: uint,
        released: bool,
    }
)

(define-map dispute-resolutions
    uint
    {
        disputed-by: principal,
        resolver: principal,
        resolution: (string-ascii 100),
        resolved-at: uint,
        compensation: uint,
    }
)

(define-public (register-verifier (reputation-stake uint))
    (let ((current-verifier (map-get? verifiers tx-sender)))
        (asserts! (is-none current-verifier) err-already-exists)
        (asserts! (>= reputation-stake (var-get min-stake-amount))
            err-insufficient-stake
        )
        (try! (stx-transfer? reputation-stake tx-sender (as-contract tx-sender)))
        (map-set verifiers tx-sender {
            is-active: true,
            reputation: u100,
            total-verifications: u0,
            successful-verifications: u0,
            stake-locked: reputation-stake,
            registered-at: stacks-block-height,
        })
        (ok true)
    )
)

(define-public (create-trade
        (importer principal)
        (goods-hash (buff 32))
        (quantity uint)
        (value uint)
        (stake-amount uint)
    )
    (let (
            (trade-id (+ (var-get trade-id-nonce) u1))
            (expiry-block (+ stacks-block-height (var-get verification-window)))
        )
        (asserts! (>= stake-amount (var-get min-stake-amount))
            err-insufficient-stake
        )
        (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
        (map-set trades trade-id {
            exporter: tx-sender,
            importer: importer,
            verifier: none,
            goods-hash: goods-hash,
            quantity: quantity,
            value: value,
            status: "pending",
            created-at: stacks-block-height,
            verified-at: none,
            expires-at: expiry-block,
            stake-amount: stake-amount,
        })
        (map-set user-stakes {
            user: tx-sender,
            trade-id: trade-id,
        } {
            amount: stake-amount,
            locked-at: stacks-block-height,
            released: false,
        })
        (var-set trade-id-nonce trade-id)
        (ok trade-id)
    )
)

(define-public (assign-verifier
        (trade-id uint)
        (verifier principal)
    )
    (let (
            (trade (unwrap! (map-get? trades trade-id) err-not-found))
            (verifier-info (unwrap! (map-get? verifiers verifier) err-not-found))
        )
        (asserts!
            (or (is-eq tx-sender (get exporter trade)) (is-eq tx-sender (get importer trade)))
            err-unauthorized
        )
        (asserts! (get is-active verifier-info) err-unauthorized)
        (asserts! (is-eq (get status trade) "pending") err-invalid-status)
        (asserts! (< stacks-block-height (get expires-at trade))
            err-trade-expired
        )
        (map-set trades trade-id
            (merge trade {
                verifier: (some verifier),
                status: "assigned",
            })
        )
        (ok true)
    )
)

(define-public (upload-document
        (trade-id uint)
        (doc-type (string-ascii 50))
        (document-hash (buff 32))
    )
    (let ((trade (unwrap! (map-get? trades trade-id) err-not-found)))
        (asserts!
            (or (is-eq tx-sender (get exporter trade)) (is-eq tx-sender (get importer trade)))
            err-unauthorized
        )
        (asserts! (< stacks-block-height (get expires-at trade))
            err-trade-expired
        )
        (map-set trade-documents {
            trade-id: trade-id,
            doc-type: doc-type,
        } {
            document-hash: document-hash,
            uploaded-by: tx-sender,
            uploaded-at: stacks-block-height,
            verified: false,
        })
        (ok true)
    )
)

(define-public (verify-trade
        (trade-id uint)
        (verification-result bool)
        (verification-notes (string-ascii 200))
    )
    (let (
            (trade (unwrap! (map-get? trades trade-id) err-not-found))
            (verifier-address (unwrap! (get verifier trade) err-unauthorized))
            (verifier-info (unwrap! (map-get? verifiers verifier-address) err-not-found))
            (new-status (if verification-result
                "verified"
                "rejected"
            ))
            (updated-verifier (merge verifier-info {
                total-verifications: (+ (get total-verifications verifier-info) u1),
                successful-verifications: (if verification-result
                    (+ (get successful-verifications verifier-info) u1)
                    (get successful-verifications verifier-info)
                ),
                reputation: (if verification-result
                    (+ (get reputation verifier-info) u5)
                    (- (get reputation verifier-info) u2)
                ),
            }))
        )
        (asserts! (is-eq tx-sender verifier-address) err-unauthorized)
        (asserts! (is-eq (get status trade) "assigned") err-invalid-status)
        (asserts! (< stacks-block-height (get expires-at trade))
            err-trade-expired
        )

        (map-set trades trade-id
            (merge trade {
                status: new-status,
                verified-at: (some stacks-block-height),
            })
        )
        (map-set verifiers verifier-address updated-verifier)

        (if verification-result
            (begin
                (try! (release-stakes trade-id))
                (try! (pay-verifier verifier-address (/ (get value trade) u100)))
                (ok verification-result)
            )
            (ok verification-result)
        )
    )
)

(define-public (confirm-receipt (trade-id uint))
    (let ((trade (unwrap! (map-get? trades trade-id) err-not-found)))
        (asserts! (is-eq tx-sender (get importer trade)) err-unauthorized)
        (asserts! (is-eq (get status trade) "verified") err-invalid-status)
        (map-set trades trade-id (merge trade { status: "completed" }))
        (ok true)
    )
)

(define-public (dispute-trade
        (trade-id uint)
        (dispute-reason (string-ascii 200))
    )
    (let ((trade (unwrap! (map-get? trades trade-id) err-not-found)))
        (asserts!
            (or (is-eq tx-sender (get exporter trade)) (is-eq tx-sender (get importer trade)))
            err-unauthorized
        )
        (asserts!
            (or (is-eq (get status trade) "verified") (is-eq (get status trade) "rejected"))
            err-invalid-status
        )
        (map-set trades trade-id (merge trade { status: "disputed" }))
        (ok true)
    )
)

(define-public (resolve-dispute
        (trade-id uint)
        (resolution (string-ascii 100))
        (compensation uint)
    )
    (let ((trade (unwrap! (map-get? trades trade-id) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (get status trade) "disputed") err-invalid-status)

        (map-set dispute-resolutions trade-id {
            disputed-by: (get exporter trade),
            resolver: tx-sender,
            resolution: resolution,
            resolved-at: stacks-block-height,
            compensation: compensation,
        })
        (map-set trades trade-id (merge trade { status: "resolved" }))

        (if (> compensation u0)
            (begin
                (try! (as-contract (stx-transfer? compensation tx-sender (get importer trade))))
                (ok true)
            )
            (ok true)
        )
    )
)

(define-public (extend-trade-deadline
        (trade-id uint)
        (additional-blocks uint)
    )
    (let ((trade (unwrap! (map-get? trades trade-id) err-not-found)))
        (asserts!
            (or (is-eq tx-sender (get exporter trade)) (is-eq tx-sender (get importer trade)))
            err-unauthorized
        )
        (asserts! (not (is-eq (get status trade) "completed")) err-invalid-status)
        (map-set trades trade-id
            (merge trade { expires-at: (+ (get expires-at trade) additional-blocks) })
        )
        (ok true)
    )
)

(define-public (deactivate-verifier)
    (let ((verifier-info (unwrap! (map-get? verifiers tx-sender) err-not-found)))
        (asserts! (get is-active verifier-info) err-invalid-status)
        (map-set verifiers tx-sender (merge verifier-info { is-active: false }))
        (try! (as-contract (stx-transfer? (get stake-locked verifier-info) tx-sender tx-sender)))
        (ok true)
    )
)

(define-public (update-min-stake (new-amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set min-stake-amount new-amount)
        (ok true)
    )
)

(define-public (update-verification-window (new-window uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set verification-window new-window)
        (ok true)
    )
)

(define-private (release-stakes (trade-id uint))
    (let (
            (trade (unwrap! (map-get? trades trade-id) err-not-found))
            (exporter-stake (map-get? user-stakes {
                user: (get exporter trade),
                trade-id: trade-id,
            }))
        )
        (match exporter-stake
            stake-info (if (not (get released stake-info))
                (begin
                    (try! (as-contract (stx-transfer? (get amount stake-info) tx-sender
                        (get exporter trade)
                    )))
                    (map-set user-stakes {
                        user: (get exporter trade),
                        trade-id: trade-id,
                    }
                        (merge stake-info { released: true })
                    )
                    (ok true)
                )
                (ok true)
            )
            (ok true)
        )
    )
)

(define-private (pay-verifier
        (verifier principal)
        (amount uint)
    )
    (as-contract (stx-transfer? amount tx-sender verifier))
)

(define-read-only (get-trade (trade-id uint))
    (map-get? trades trade-id)
)

(define-read-only (get-verifier (verifier principal))
    (map-get? verifiers verifier)
)

(define-read-only (get-document
        (trade-id uint)
        (doc-type (string-ascii 50))
    )
    (map-get? trade-documents {
        trade-id: trade-id,
        doc-type: doc-type,
    })
)

(define-read-only (get-user-stake
        (user principal)
        (trade-id uint)
    )
    (map-get? user-stakes {
        user: user,
        trade-id: trade-id,
    })
)

(define-read-only (get-dispute-resolution (trade-id uint))
    (map-get? dispute-resolutions trade-id)
)

(define-read-only (get-trade-count)
    (var-get trade-id-nonce)
)

(define-read-only (get-min-stake)
    (var-get min-stake-amount)
)

(define-read-only (get-verification-window)
    (var-get verification-window)
)

(define-read-only (is-trade-expired (trade-id uint))
    (match (map-get? trades trade-id)
        trade (> stacks-block-height (get expires-at trade))
        false
    )
)

(define-read-only (calculate-verifier-rating (verifier principal))
    (match (map-get? verifiers verifier)
        verifier-info (if (> (get total-verifications verifier-info) u0)
            (/ (* (get successful-verifications verifier-info) u100)
                (get total-verifications verifier-info)
            )
            u0
        )
        u0
    )
)

(define-read-only (get-active-verifiers)
    (ok "use list-verifiers with pagination")
)

(define-read-only (get-trades-by-exporter (exporter principal))
    (ok "use query functions with pagination")
)

(define-read-only (get-trades-by-importer (importer principal))
    (ok "use query functions with pagination")
)

(define-read-only (get-pending-verifications (verifier principal))
    (ok "use query functions with pagination")
)

(define-public (emergency-withdraw (trade-id uint))
    (let ((trade (unwrap! (map-get? trades trade-id) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> stacks-block-height (+ (get expires-at trade) u1440))
            err-invalid-status
        )
        (try! (release-stakes trade-id))
        (map-set trades trade-id (merge trade { status: "emergency-withdrawn" }))
        (ok true)
    )
)

(define-public (batch-verify-documents
        (trade-id uint)
        (doc-types (list 10 (string-ascii 50)))
    )
    (let (
            (trade (unwrap! (map-get? trades trade-id) err-not-found))
            (verifier-address (unwrap! (get verifier trade) err-unauthorized))
        )
        (asserts! (is-eq tx-sender verifier-address) err-unauthorized)
        (fold verify-single-document doc-types {
            trade-id: trade-id,
            success: true,
        })
        (ok true)
    )
)

(define-private (verify-single-document
        (doc-type (string-ascii 50))
        (context {
            trade-id: uint,
            success: bool,
        })
    )
    (let (
            (trade-id (get trade-id context))
            (document (map-get? trade-documents {
                trade-id: trade-id,
                doc-type: doc-type,
            }))
        )
        (match document
            doc-info (begin
                (map-set trade-documents {
                    trade-id: trade-id,
                    doc-type: doc-type,
                }
                    (merge doc-info { verified: true })
                )
                context
            )
            context
        )
    )
)

(define-public (stake-additional
        (trade-id uint)
        (additional-amount uint)
    )
    (let (
            (trade (unwrap! (map-get? trades trade-id) err-not-found))
            (current-stake (unwrap!
                (map-get? user-stakes {
                    user: tx-sender,
                    trade-id: trade-id,
                })
                err-not-found
            ))
        )
        (asserts!
            (or (is-eq tx-sender (get exporter trade)) (is-eq tx-sender (get importer trade)))
            err-unauthorized
        )
        (asserts! (not (get released current-stake)) err-invalid-status)
        (try! (stx-transfer? additional-amount tx-sender (as-contract tx-sender)))
        (map-set user-stakes {
            user: tx-sender,
            trade-id: trade-id,
        }
            (merge current-stake { amount: (+ (get amount current-stake) additional-amount) })
        )
        (ok true)
    )
)

(define-public (cancel-trade (trade-id uint))
    (let ((trade (unwrap! (map-get? trades trade-id) err-not-found)))
        (asserts! (is-eq tx-sender (get exporter trade)) err-unauthorized)
        (asserts! (is-eq (get status trade) "pending") err-invalid-status)
        (try! (release-stakes trade-id))
        (map-set trades trade-id (merge trade { status: "cancelled" }))
        (ok true)
    )
)

(define-public (rate-verifier
        (verifier principal)
        (rating uint)
    )
    (let ((verifier-info (unwrap! (map-get? verifiers verifier) err-not-found)))
        (asserts! (<= rating u5) err-invalid-verification)
        (asserts! (>= rating u1) err-invalid-verification)
        (map-set verifiers verifier
            (merge verifier-info { reputation: (+ (get reputation verifier-info) rating) })
        )
        (ok true)
    )
)

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-trade-statistics)
    {
        total-trades: (var-get trade-id-nonce),
        current-block: stacks-block-height,
        min-stake: (var-get min-stake-amount),
        verification-window: (var-get verification-window),
    }
)
