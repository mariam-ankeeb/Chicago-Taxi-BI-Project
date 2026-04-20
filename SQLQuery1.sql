--MILESTONE1
Create Schema Landing;
Create Schema Staging;
Create Schema DW;
alter Schema Landing Transfer dbo.TaxiRawData;
select count(*) from Landing.TaxiRawData;
select top(10)* from Landing.TaxiRawData;

--MILESTONE2
select count(*) from Landing.TaxiRawData where Pickup_Community_Area is null;
--23195
select count(*) from Landing.TaxiRawData where Company is null or Company = 'NULL' ;
--0
select count(Payment_Type) as number_of_usage , Payment_Type from Landing.TaxiRawData 
group by Payment_Type;
-- 112964 pycard  
--45868 unknown
--127520 Mobile
--253722 Cash
--738 No charge
--324125 Credit Card
--310 Dispute
select MAX(Trip_Start_Timestamp),Min(Trip_Start_Timestamp) from Landing.TaxiRawData;
--max: 3/1/2024     min : 1/1/2024
select count(*) from Landing.TaxiRawData where Trip_Seconds = 0 or Trip_Seconds is null;
--16719
select count(*) from Landing.TaxiRawData where Fare <= 0 or Fare is null;
--3561
select count(*) from Landing.TaxiRawData where Trip_Miles <= 0 or Trip_Miles is null;
--86844
SELECT trip_id, COUNT(*) FROM landing.TaxiRawData GROUP BY trip_id having COUNT(*) > 1;
--0


--MILESTONE3
CREATE TABLE Staging.TaxiClean_TSQL (
trip_id nvarchar(100) not null,              
trip_start_timestamp     Datetime2 not null,
trip_start_date     Date     Not null ,          
trip_seconds        INT       Not Null,     
trip_duration_minutes    Decimal(10,2)  Not null,
trip_miles               decimal (10,4) not null,
pickup_community_area    int  null,
dropoff_community_area   int null,
fare   Decimal(10,2)     Not null,             
tips       Decimal(10,2)     Not null,                
tolls        Decimal(10,2)     Not null,              
extras          Decimal(10,2)     Not null,           
payment_type   nvarchar(50)  not null,          
company       nvarchar(200) not null          
);




CREATE OR ALTER PROCEDURE Staging.Sql_CleanTaxi
AS
BEGIN
SET NOCOUNT ON;-- Log start time
DECLARE @StartTime DATETIME2 = GETDATE();
DECLARE @RowsIn INT, @RowsOut INT;
SELECT @RowsIn = COUNT(*) FROM landing.TaxiRawData;-- Truncate destination
TRUNCATE TABLE staging.TaxiClean_TSQL;-- Insert cleaned rows using a CTE to deduplicate first
;
WITH Deduped AS (
SELECT *, ROW_NUMBER() OVER (
PARTITION BY trip_id
ORDER BY trip_start_timestamp
) AS rn
FROM landing.TaxiRawData
WHERE trip_id IS NOT NULL
AND LTRIM(RTRIM(trip_id)) <> ''
)

INSERT INTO staging.TaxiClean_TSQL (
        trip_id,
        trip_start_timestamp,
        trip_start_date,
        trip_seconds,
        trip_duration_minutes,
        trip_miles,
        pickup_community_area,
        dropoff_community_area,
        fare,
        tips,
        tolls,
        extras,
        payment_type,
        company
)
SELECT-- Natural key
        LTRIM(RTRIM(trip_id)),-- Timestamps: Chicago data uses M/D/YYYY H:MM:SS AM format
        TRY_CAST(trip_start_timestamp AS DATETIME2),
        CAST(TRY_CAST(trip_start_timestamp AS DATETIME2) AS DATE),-- Numeric measures
        TRY_CAST(trip_seconds AS INT),
ROUND(TRY_CAST(trip_seconds AS DECIMAL(10,2)) / 60.0, 2),
        TRY_CAST(trip_miles AS DECIMAL(10,4)),-- Location (NULL allowed)
        TRY_CAST(NULLIF(LTRIM(RTRIM(pickup_community_area)), '') AS INT),
        TRY_CAST(NULLIF(LTRIM(RTRIM(dropoff_community_area)), '') AS INT),-- Financial measures
        TRY_CAST(fare AS DECIMAL(10,2)),-- Tips: 0 for non-card payments (business rule)
CASE
WHEN LTRIM(RTRIM(UPPER(payment_type))) = 'CREDIT CARD'
THEN ISNULL(TRY_CAST(tips AS DECIMAL(10,2)), 0)
ELSE 0
END,
        ISNULL(TRY_CAST(tolls AS DECIMAL(10,2)), 0),
        ISNULL(TRY_CAST(extras AS DECIMAL(10,2)), 0),-- Standardised payment type (title case equivalent)
CASE LTRIM(RTRIM(UPPER(ISNULL(payment_type,''))))
WHEN 'CASH' THEN 'Cash'
WHEN 'CREDIT CARD' THEN 'Credit Card'
WHEN 'NO CHARGE' THEN 'No Charge'
WHEN 'DISPUTE' THEN 'Dispute'
WHEN 'PRORATE' THEN 'Prorate'
ELSE 'Unknown'
END,-- Company: trim + default
        ISNULL(
NULLIF(LTRIM(RTRIM(company)), ''),
'Unknown'
)
FROM Deduped
WHERE rn = 1-- Remove duplicates-- Filter: bad fare
AND TRY_CAST(fare AS DECIMAL(10,2)) > 0-- Filter: bad trip_seconds
AND TRY_CAST(trip_seconds AS INT) > 0-- Filter: bad trip_miles
AND TRY_CAST(trip_miles AS DECIMAL(10,4)) > 0-- Filter: timestamp must parse
AND TRY_CAST(trip_start_timestamp AS DATETIME2) IS NOT NULL;
SELECT @RowsOut = COUNT(*) FROM staging.TaxiClean_TSQL;-- Print reconciliation summary
END;

EXEC staging.Sql_CleanTaxi;
select count(*) from Staging.TaxiClean_TSQL
select top(5)* from Staging.TaxiClean_TSQL
select count(*) from Staging.TaxiClean_Python


--MILESTONE4
create table DW.DimDate(
DateKey INT primary key,
FullDate Date,
Year int ,
Quarter int,
Month int,
MonthName Varchar(50),
DayOfWeek INT,
DayName Varchar(50),
IsWeekEnd BIT
);


DECLARE @StartDate DATE = '2024-01-01';
DECLARE @EndDate DATE = '2024-12-31';

WITH DateSeries AS (
SELECT @StartDate AS d
UNION ALL
SELECT DATEADD(DAY, 1, d)
FROM DateSeries
WHERE d < @EndDate
)
INSERT INTO dw.DimDate
SELECT
    CAST(FORMAT(d, 'yyyyMMdd') AS INT) AS DateKey,
    d                                   AS FullDate,
YEAR(d) AS Year,
    DATEPART(QUARTER, d) AS Quarter,
MONTH(d) AS Month,
    DATENAME(MONTH, d) AS MonthName,
    DATEPART(WEEKDAY, d) AS DayOfWeek,
    DATENAME(WEEKDAY, d) AS DayName,
CASE WHEN DATEPART(WEEKDAY, d) IN (1, 7) THEN 1 ELSE 0 END AS IsWeekend
FROM DateSeries
OPTION (MAXRECURSION 1000);
GO
SELECT COUNT(*) AS DateRows FROM DW.DimDate;-- Should be 365 for a full year


create table DW.DimPaymentType(
PaymentTypeKey INT IDENTITY PRIMARY KEY,
PaymentTypeCode VARCHAR(50),
);

INSERT INTO DW.DimPaymentType(PaymentTypeCode)
SELECT DISTINCT (payment_type)  AS PaymentTypeCode
From Staging.TaxiClean_TSQL

select * from DW.DimPaymentType


create table DW.DimCompany(
CompanyKey INT IDENTITY PRIMARY KEY,
CompanyName Varchar(200)
)

INSERT INTO DW.DimCompany(CompanyName)
SELECT DISTINCT (Company) from Staging.TaxiClean_TSQL

select * from DW.DimCompany



create table DW.DimLocation(
LocationKey INT IDENTITY PRIMARY KEY,
CommunityAreaNumber INT
)

Insert into Dw.DimLocation(CommunityAreaNumber)
select distinct(pickup_community_area) from Staging.TaxiClean_TSQL
UNION 
select distinct(dropoff_community_area) from Staging.TaxiClean_TSQL
 
select * from dw.DimLocation 



create table DW.FactTrip(
TripKey INT IDENTITY PRIMARY KEY,
TripID Varchar(100),
DateKey INT foreign key references DW.DimDate(DateKey),
CompanyKey INT  foreign key references DW.DimCompany(CompanyKey),
PaymentTypeKey INT  foreign key references DW.DimPaymentType(PaymentTypeKey),
PickupLocationKey INT  foreign key references DW.DimLocation(LocationKey),
DropoffLocationKey INT  foreign key references DW.DimLocation(LocationKey),
FareAmount Decimal(10,2),
TipAmount Decimal(10,2),
TollsAmount Decimal(10,2),
ExtrasAmount Decimal(10,2),
TripSeconds INT,
TripMiles decimal (10,4),
TripDurationMinutes Decimal(10,2)
)

INSERT INTO dw.FactTrip (
        TripID, DateKey, CompanyKey, PaymentTypeKey,
        PickupLocationKey, DropoffLocationKey,
        FareAmount, TipAmount, TollsAmount, ExtrasAmount,
        TripSeconds, TripMiles, TripDurationMinutes
)
SELECT
        s.trip_id,-- DateKey: YYYYMMDD integer
        CAST(FORMAT(s.trip_start_date, 'yyyyMMdd') AS INT),
        ISNULL(c.CompanyKey, 1),
        ISNULL(p.PaymentTypeKey, 1),
        ISNULL(lp.LocationKey, 1),-- 1 = Unknown-- DropoffLocationKey
        ISNULL(ld.LocationKey, 1),
        s.fare, s.tips, s.tolls, s.extras,
        s.trip_seconds, s.trip_miles, s.trip_duration_minutes
FROM staging.TaxiClean_TSQL s-- Lookup company
LEFT JOIN dw.DimCompany c
ON c.CompanyName = s.company
LEFT JOIN dw.DimPaymentType p
ON p.PaymentTypeCode = s.payment_type-- Lookup pickup location
LEFT JOIN dw.DimLocation lp
ON lp.CommunityAreaNumber = s.pickup_community_area-- Lookup dropoff location
LEFT JOIN dw.DimLocation ld
ON ld.CommunityAreaNumber = s.dropoff_community_area;











truncate table DW.FactTrip
EXEC Staging.Sql_CleanTaxi











