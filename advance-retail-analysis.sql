-- create table layout to import csv
create table sales_sql (
	transaction_id   VARCHAR(225),
    customer_id      VARCHAR(255),
    customer_name    VARCHAR(100),
    customer_age     INT,
    gender           VARCHAR(10),
    product_id       VARCHAR(255),
    product_name     VARCHAR(255),
    product_category VARCHAR(255),
    quantiy          INT,           
    prce             NUMERIC(10,2),
    payment_mode     VARCHAR(50),
    purchase_date    DATE,
    time_of_purchase TIME,
    status           VARCHAR(50)
);


--change date format because sql throwing errors 
SET datestyle = 'ISO, DMY';

COPY sales_sql
FROM 'E:/raw_sales.csv'
WITH (
    FORMAT csv,
    HEADER true
);

select * from sales_sql 
limit 5;
-- data cleaning,fix column names, standarise values 
--first rename columns
alter table sales_sql
--rename column quantiy to quantity;
rename column prce to  price;

-- check all columns
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'sales_sql';

-- normalizing gender, payment mode
update sales_sql
set gender= case
	when upper(gender) in ('F','f','FEMALE') then 'Female'
	when upper (gender) in ('M', 'm','MALE') then 'Male'
	else gender
end ;
--standarizing payment mode
select distinct payment_mode
from  sales_sql;
update sales_sql
set payment_mode=case
when upper(payment_mode) in ('CC') then 'Credit Card'
else payment_mode
end;

--1. EDA
--Row counts
select 
	count(*) as total_transaction,
	count(distinct transaction_id) as unique_transactions,
	count(distinct customer_id) as unique_customers,
	count(distinct product_id) as unique_products,
	min(purchase_date) as first_order,
	max(purchase_date) as last_order
from sales_sql;
-- null audits
select 
	count(*) filter (where customer_id is null or customer_id='') as null_customers_id,
	count(*) filter( where customer_name is null or customer_name='') as null_customers,
	count(*) filter (where transaction_id is null or transaction_id='') as null_transactions,
	count(*) filter (where product_id is null or product_id='') as null_products,
	count(*) filter (where payment_mode is null or payment_mode='') as null_payment_mode,
	count(*) filter (where price is null or price=0) as null_price
from sales_sql;

-- duplicate detection 
select 
	transaction_id,
	count(*) as occurance
from sales_sql
group by transaction_id
having count(*)>1
order by occurance desc;
	
-- status distribution 
select
	status,
	count(*) as transactions,
	round(count(*)*100.0/sum(count(*)) over(),2) as percentage
from sales_sql
group by status
order by transactions desc;

--before doing more analysis let's create a view for further analysis
create view clean_view as
select
	transaction_id,
    customer_id,
    customer_name,
    customer_age ,
    gender ,
    product_id ,
    product_name,
    product_category,
    quantity,           
    price ,
    payment_mode ,
    purchase_date,
    time_of_purchase,
    status,
	--drived columns
	round(quantity*price,2) as total_revenue,
	date_trunc('month' ,purchase_date) as revenue_month,
	extract(year  from purchase_date) as purchase_year,
	extract(month from purchase_date) as month_number,
	to_char(purchase_date, 'Mon YYYY') as month_label,
	--time slot
	case 
	when extract(hour from time_of_purchase) between 6 and 11 then 'Morning'
	when extract(hour from time_of_purchase) between 12 and 16 then 'Afternoon'
	when extract(hour from time_of_purchase) between 17 and 20 then 'Evening'
	else 'Night'
end as time_slot,
	--age_group
	case
	when customer_age between 18 and 25 then '18-25'
	when customer_age between 26 and 35 then '26-35'
	when customer_age between 36 and 45 then '36-45'
	when customer_age between 46 and 60 then '46-60'
	else 'others'
end as age_group
from sales_sql
where transaction_id  IS NOT NULL
  AND status  IS NOT NULL
  AND status <> ''
  AND gender IS NOT NULL
  AND gender <> '';



--2. — Sales Performance
--monthly revenue trend
select
	month_number,
	sum(total_revenue) as total_revenue
from clean_view
group by month_number
order by month_number;
	
-- month-over-month growth
with current_month as (
select
	month_number,
	sum(total_revenue) as monthly_revenue
from clean_view
where status='delivered'
group by month_number
),
previous_month as(
select
	month_number,
	monthly_revenue,
	lag(monthly_revenue) over (
	order by month_number
	) as previous_month
from current_month
)
select	
	
	month_number,
	monthly_revenue,
	previous_month,
	round(
		((monthly_revenue-previous_month)/nullif(previous_month,0)*100)
		,2) as mom_growth
from previous_month
order by month_number;

--revenue by category with share %
select	
	product_category,
	sum(total_revenue) as total_revenue,
	round(sum(total_revenue) filter( where status='delivered') ,2) as revenue_delivered,
	round(
		sum(total_revenue)*100.0/
		sum(sum(total_revenue)) over(),
	2) as revenue_percnt
from clean_view
group by product_category;

--top 10 products by revenue
select
	product_name,
	product_category,
	sum(quantity) as unit_sold,
	sum(total_revenue) as total_revenue,
	round(avg(price),2) as avg_unit_price
from clean_view
group by product_name, product_category
order by total_revenue desc
limit 10;

-- payment mode breakdown
select
	payment_mode,
	count(*) as transactions,
	round(sum(total_revenue),2) as total_revenue,
	round(
		count(*) *100.0/sum(count(*))over()
	,2)as payment_percnt
from clean_view
group by payment_mode
order by total_revenue desc;

--3 — Fulfilment Analysis
--Delivery/return/cancellation rates per category
select
	product_category,
	count(*) filter(where status='delivered') as delivered,
	count(*) filter (where status='returned') as returned,
	count(*) filter (where status='cancelled') as cancelled,
	count(*) filter (where status='pending') as pending,
	round( count(*) filter(where status='delivered') *100.0/count(*)
	,2) as delivered_pct,
	round( count(*) filter(where status='returned')*100.0/count(*)
	,2)as returned_pct
from clean_view
group by product_category;

--return rate by payment mode,
select
	payment_mode,
	count(*) as total_transactions,
	count(*) filter (where status='returned') as returned,
	round(
		count(*) filter (where status='returned') *100.0/count(*)
	,2) as return_pct
from clean_view
group by payment_mode
order by return_pct desc;

--cancellation trend by month

select
	month_number,
	count(*) as total_transactions,
	count(*) filter (where status='cancelled') as cancelled_orders,
	round(
		count(*) filter(where status='cancelled')*100.0/count(*)
	,2) cancelled_pct
from clean_view
group by month_number
order by cancelled_orders desc;

-- 4 — Customer Analytics
--Lifetime value segmentation (VIP / High / Mid / Low)
with customer_stats as (
select
	customer_id,
	customer_name,
	count(distinct transaction_id) as total_transactions,
	round(sum(total_revenue),2) as lifetime_revenue,
	max(purchase_date) as last_order,
	min(purchase_date) as first_order,
	count(distinct product_category) as category_bought
from clean_view
group by  customer_id, customer_name
)
select
	customer_id,
	customer_name,
	total_transactions,
	lifetime_revenue,
	last_order,
	first_order,
	category_bought,
	case
		when lifetime_revenue>=200000 then 'VIP'
		when lifetime_revenue>=10000 then 'High'
		when lifetime_revenue>=2000 then 'Mid-Value'
		else 'Low'
	end as customer_segments
from customer_stats
order by lifetime_revenue desc;

-- top 10 customers
select 
	customer_id,
	customer_name,
	count(*) as orders,
	sum(total_revenue) as total_spent,
	round(avg(total_revenue),2) as avg_order_value
from clean_view
group by customer_id, customer_name
order by total_spent desc
limit 10;
	
--revenue by age group + gender
select
	gender,
	age_group,
	round(sum(total_revenue),2) as revenue_
from clean_view
group by age_group,gender
order by revenue_ desc;

-- category preference by age
select
	age_group,
	product_category,
	count(*) as orders,
	round(sum(total_revenue),2) as revenue,
	rank() over(
			partition by age_group
			order by sum(total_revenue) desc
	) as category_rank
from clean_view
group by age_group,product_category
order by age_group, category_rank;

-- repeat vs one-time buyer split
with order_count as (
select
	customer_id,
	count(distinct transaction_id) as order_numbers
from clean_view
group by customer_id
)
select
	case when order_numbers =1 then 'One-time buyer' else 'Repeat buyer' end as buyer_type,
	count(*) as customers,
	round(avg(order_numbers),2) as avg_order_per_customer
from order_count
group by buyer_type;

--5 — Time Behaviour
--Orders by Morning/Afternoon/Evening/Night
select
	time_slot,
	count(*) as orders,
	round(sum(total_revenue),2) as total_sales,
	round( avg(total_revenue),2) as avg_order
from clean_view
group by time_slot
order by  orders desc;

--day-of-week patterns,
select
	to_char(purchase_date, 'day') as day_name,
	extract(dow from purchase_date) as day_num,
	count(*) as orders,
	round(sum(total_revenue),2) as revenue
from clean_view
group by day_name, day_num
order by orders desc;

--peak hour analysis
select
	extract(hour from time_of_purchase) as peak_hour,
	count(*) as orders,
	round(sum(total_revenue),2) as revenue
from clean_view
group by peak_hour
order by orders desc;

--Advanced SQL
--Running totals
select
	month_label,
	extract('month' from revenue_month) as mon,
	round(sum(total_revenue),2) as revenue,
	round(
        sum(sum(total_revenue)) over (
            order by revenue_month
        ),
        2
    ) AS running_totals
from clean_view
where status='delivered'
group by month_label,revenue_month
order by revenue_month;

--product ranking
select
	product_category,
	product_name,
	sum(total_revenue) as revenue,
	rank() over(
			partition by product_category
			order by sum(total_revenue) desc
	) as product_rank,
	dense_rank() over (
			partition by product_category
			order by sum(total_revenue) desc
	) as dense_rank_product

from clean_view
group by product_category,product_name
order by product_category,dense_rank_product;

--3-month rolling average
with monthly_revenue as(
select
	revenue_month,
	month_label,
	round(sum(total_revenue),2) as revenue
from clean_view
group by revenue_month,month_label
)

select
	month_label,
	revenue,
	round(
		avg(revenue) over(
		order by revenue_month
		rows between 2 preceding  and current row
		)
	,2) as rolling_avg
from monthly_revenue
order by revenue_month;

--customer frequency percentile

with customer_orders as(
select
	customer_id,
	customer_name,
	count(distinct transaction_id) as order_count
from clean_view
group by customer_id, customer_name
)
select 
	customer_id,
	order_count,
	ntile(4) over(order by order_count) as qurantile,
	round(
	cast(percent_rank() over(order by order_count)*100  as numeric),2)as percentile_rank
from customer_orders
order by order_count desc;
	
--customer lifespan calculation
select
	customer_id,
	customer_name,
	min(purchase_date) as first_purchase,
	max(purchase_date) as last_order,
	count(*) as total_orders,
	max(purchase_date) - min(purchase_date) as customer_lifespan_days
from clean_view
group by customer_id,customer_name
order by customer_lifespan_days desc;
	
--Revenue leakage
select
	status,
	count(*) as total_orders,
	round(sum(total_revenue),2) as total_revenue
from clean_view
where status in ('returned', 'cancelled')
group by status;

--Products with high return rate
select
	product_category,
	count(*) as orders,
	count(*) filter(where status='returned') as returned_orders,
	round ( count(*) filter(where status='returned')*100/count(*) ,2) as returned_pct,
	round(sum(total_revenue) filter(where status='returned'),2) as lost_revenue
from clean_view
group by product_category
having count(*)>=10
order by returned_pct desc;

--high-value pending orders
select
	customer_name,
	transaction_id,
	product_name,
	quantity,
	round(total_revenue,2) as pending_revenue
from clean_view
where status='pending'
order by pending_revenue desc
limit 20;



--avg order value	
select sum(total_revenue)/count(distinct transaction_id) as aov
from clean_view
	
