# Metric definitions: Weekly unusual order activity report

**Requested by:** Risk & Compliance team
**Prepared by:** Sirous Namjoo · **Status:** draft for sign-off · **Date:** 27 Oct 2026
**Source:** Olist public e-commerce dataset (`olist_orders`, `olist_order_items`, `olist_sellers`, `olist_customers`, `olist_order_payments`)

## The request

> A weekly report on unusual customer activity: orders cancelled or refunded, by seller and region, with week-on-week change. The team needs to trust the numbers.

## Key definitions

| Term | Definition | Source field |
|---|---|---|
| **Order** | One row in `orders` (one `order_id`). Orders are unique: 99,441 rows, 99,441 IDs. | `orders.order_id` |
| **Unusual order** | An order whose current status is `canceled` or `unavailable`. | `orders.order_status` |
| **Canceled** | The order was cancelled after it was placed. | `order_status = 'canceled'` |
| **Unavailable** | The order was paid but the product couldn't be supplied. | `order_status = 'unavailable'` |
| **Week** | Monday to Sunday, based on the **purchase date** of the order. | `order_purchase_timestamp` |
| **Unusual rate** | Unusual orders ÷ all orders purchased that week (any status), as a %. | — |
| **Value paid on unusual orders** | Sum of all payments recorded against unusual orders (R$). Whether it was refunded is unknown. | `order_payments.payment_value` |
| **Seller** | The seller on the order's items. In the window, every attributable unusual order has exactly one seller. If a future refresh brings in a multi-seller order, it is counted under each of its sellers in the by-seller view, and that view must say so. | `order_items.seller_id` |
| **Seller region** | The state of the seller. | `sellers.seller_state` |
| **Customer region** | The state of the customer. Covers every order, including those with no seller. | `customers.customer_state` |
| **Region "Other"** | States with fewer than 10 unusual orders in the whole window are grouped as "Other", so small states don't create noise and totals still reconcile. Applies to both region views. | — |
| **Cancellation stage** | How far a canceled order got before cancelling: *before approval* (no approval date), *before shipping* (approved, no carrier date), *in transit* (shipped, no delivery date), *after delivery* (has a delivery date; possible return). `unavailable` orders are shown as their own stage. Checked: no order skips a stage. | `order_approved_at`, `order_delivered_carrier_date`, `order_delivered_customer_date` |
| **Unattributed** | An unusual order with no rows in `order_items`, so it has no seller. Shown as its own row and never dropped. | — |

## Week-on-week change

- **Absolute change** = this week's unusual orders − last week's.
- **Rate change** = this week's unusual rate − last week's, in percentage points.
- A **% change** is shown only when last week had 10 or more unusual orders. The median week has 12, so a % on smaller bases (e.g. 2 → 4 = +100%) would mislead.

## Reporting window

**Mon 2 Jan 2017 to Sun 26 Aug 2018** (86 full weeks).
- Before 2017, the data is too thin (Sep 2016: 4 orders; Dec 2016: 1).
- After 26 Aug 2018, the data stops: the week from 27 Aug has 130 orders against a median of about 1,000, and Sep–Oct 2018 holds 20 orders, 19 of them unusual.

## Baseline totals for the window (the numbers every view must reconcile to)

| Measure | Value |
|---|---|
| All orders | 98,962 |
| Unusual orders | 1,168 (canceled 566 · unavailable 602) |
| … of which unattributed (no seller) | 720 (62%) |
| Value paid on unusual orders | R$254,721.50 |
| Unusual orders with no payment record | 0 (3 canceled orders have a R$0 `not_defined` payment) |

## Known limitations (tell the stakeholder up front)

1. **No refund data.** Olist doesn't record refunds, so the report covers only cancellations and unavailable orders. The money paid on these orders (R$254.7k) is reported, but whether it was returned is unknown.
2. **Most unusual orders have no seller.** 62% of them have no item rows, almost all of them `unavailable` orders. The by-seller view can explain fewer than 4 in 10 unusual orders. The by-customer-region view covers all of them.
3. **No cancellation date.** Orders are counted in the week they were **purchased**, not the week they were cancelled. An order still in progress (1,699 in the window) can be cancelled later, so recent weeks may change after the report is first sent.
4. **Seller counts are small.** 334 sellers have at least one unusual order; 258 of them have only one, and the highest is 9 over the whole period. Week-on-week change **per seller** would be noise. **Recommendation:** show sellers over the trailing 4 weeks and for the full period, ranked, with week-on-week change at the total and region level only.
5. **Status is a snapshot.** `order_status` is the status when the dataset was extracted, not a history of changes.

## Questions for the stakeholder before build

1. Is `canceled` + `unavailable` the right definition of "unusual", or should late or undelivered orders be included too?
2. Is the 4-week trailing seller view acceptable instead of per-seller week-on-week change?
3. Which region matters more for your decisions: the seller's state or the customer's?
