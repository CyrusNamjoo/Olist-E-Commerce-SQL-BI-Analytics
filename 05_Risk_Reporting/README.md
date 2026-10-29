# Weekly Unusual Order Activity: Risk & Compliance Report

A reporting layer of four PostgreSQL views showing cancelled and unavailable orders each week, by seller region and by seller, with week-on-week change. Every view reconciles to the same baseline totals.

**Requested by:** Risk & Compliance · **Built by:** Sirous Namjoo · **Status:** v1, Oct 2026
**Practice brief based on:** the VGW Business Intelligence Analyst job ad (Perth)

## The request

> The Risk & Compliance team needs a weekly report on unusual customer activity: orders cancelled or refunded, by seller and region, with week-on-week change. They need to trust the numbers.

## What's in it

| View | One row = | Answers |
|---|---|---|
| `reporting.v_unusual_orders` | one unusual order | The base list. Every other view counts from here, so "unusual" is defined in one place. |
| `reporting.v_weekly_totals` | one week | How many unusual orders, what share of all orders, and the change from last week? |
| `reporting.v_weekly_by_region` | one week × seller region | Where are unusual orders coming from, and is any region getting worse? |
| `reporting.v_seller_trailing_4w` | one week × seller | Which sellers had the most unusual orders in the last 4 weeks? |

## Key results (2 Jan 2017 – 26 Aug 2018)

- **1,168 unusual orders** out of 98,962 (566 canceled, 602 unavailable). R$254,721.50 had been paid on them.
- **62% (720) can't be traced to a seller.** They have no items, and almost all of them are `unavailable` orders. This is the largest single group in the report.
- Of the orders that can be traced, **SP sellers account for 73%** (327 of 448).
- Cancelled orders stop at different stages: 141 before approval, 409 after approval but before shipping, 69 in transit, 6 after delivery (possible returns).
- Example flag: in the week of 20 Aug 2018, one SP seller had **5 unusual orders in 4 weeks**. The next highest sellers had 2.

## Data source

Olist Brazilian e-commerce public dataset, loaded into PostgreSQL schema `raw`. Tables used: `orders`, `order_items`, `sellers`, `customers`, `order_payments`.

**Setup:** run this repo's `01_SQL/01_database_setup.sql`, `02_raw_tables.sql` and `03_data_import.sql` first to create and load the `raw` schema.

## Definitions and assumptions

Full definitions: [`docs/metric_definitions.md`](docs/metric_definitions.md). Table exploration notes: [`docs/data_notes.md`](docs/data_notes.md).

- **Unusual** = current status `canceled` or `unavailable`.
- **Week** = Monday to Sunday, based on the **purchase** date.
- **Region** = the seller's state. States with fewer than 10 unusual orders in the window are grouped as **"Other"**. Orders with no seller are shown as **"Unattributed"**, never dropped.
- **% change** is shown only when last week had 10 or more unusual orders. Smaller bases make the % misleading.

## Limitations (read before using the numbers)

1. **No refund data.** Olist doesn't record refunds. The report shows money paid on unusual orders, but not whether it was returned.
2. **No cancellation date.** Orders are counted in the week they were bought. An order still in progress can be cancelled later, so **recent weeks can change after the report is first sent**.
3. **Status is a snapshot** taken when the data was extracted, not a history.
4. **`orders_last_4w` is a rolling count.** Each order appears in up to 4 report weeks. **Never sum it across weeks** (e.g. in a Power BI total), because the total means nothing.
5. **Seller counts are small.** Most sellers have 1 unusual order in the whole window, which is why sellers are shown over 4 weeks and not week by week.

## How to refresh

Run the files in order. Each view depends on the one before it:

1. `sql/01_v_unusual_orders.sql`
2. `sql/02_v_weekly_totals.sql`
3. `sql/03_v_weekly_by_region.sql`
4. `sql/04_v_seller_trailing_4w.sql`

Each file ends with **reconciliation checks** that have the expected values written next to them. Run them after every refresh. If a check fails, don't send the report until you've found out why.

When new data arrives:
- Update the **date window** in views 1 and 2 (`2017-01-02` / `2018-08-27`).
- Re-check that **no unusual order has more than one seller** (view 1, check 2). If one does, it appears once per seller in views 3–4, and the totals no longer reconcile.
- Re-check the **"Other" grouping**. A state can cross the 10-order threshold.
- If you change a view's columns, PostgreSQL may refuse `CREATE OR REPLACE` while other views depend on it. Drop the dependent views first, then rerun all four files in order.

## Not built yet (possible next versions)

- **Customer-region view.** The definitions describe one. It would cover all 1,168 orders, including the Unattributed 62%.
- **Cancellation stage** as a column in view 1, so Risk can see *where* orders fail, not just how many.
- A **Power BI page** on top of these views (Module 2).
