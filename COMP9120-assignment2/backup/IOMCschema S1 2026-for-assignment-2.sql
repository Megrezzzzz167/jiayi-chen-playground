SET
	DATESTYLE = 'ISO, DMY';

DROP TABLE IF EXISTS ATHLETE CASCADE;

DROP TABLE IF EXISTS ATHLETE_IMAGES CASCADE;

DROP TABLE IF EXISTS EQUIPMENT CASCADE;

DROP TABLE IF EXISTS TRAVEL_STIPEND CASCADE;

DROP TABLE IF EXISTS MEDICAL_PACKAGE CASCADE;

--DROP TABLE IF EXISTS MEDICAL_PACKAGES CASCADE;

DROP TABLE IF EXISTS TRIALS CASCADE;

DROP TABLE IF EXISTS AMATEUR CASCADE;

DROP TABLE IF EXISTS PROFESSIONAL CASCADE;

DROP TABLE IF EXISTS OFFICIAL CASCADE;

DROP TABLE IF EXISTS PARTICIPATION CASCADE;

DROP TABLE IF EXISTS OVERSEES CASCADE;

DROP TABLE IF EXISTS SPONSORSHIP_PAYMENT CASCADE;

DROP TABLE IF EXISTS PROFESSIONAL_MEDICAL_SELECTION CASCADE;

CREATE TABLE ATHLETE (
	ATHLETE_ID INT PRIMARY KEY,
	FIRSTNAME VARCHAR(100) NOT NULL,
	LASTNAME VARCHAR(100) NOT NULL,
	DOB DATE NOT NULL,
	HEIGHT DECIMAL(5, 2),
	WEIGHT DECIMAL(5, 2),
	NATIONALITY VARCHAR(50),
	EMAIL TEXT NOT NULL,
	PASSPORT_NUMBER INT NOT NULL UNIQUE,
	MOBILE_NUMBER INT NOT NULL,
	TSDATE DATE NOT NULL,
	UNIQUE (ATHLETE_ID, TSDATE),
	BIO TEXT
);

-- Multi-valued attribute for Images
CREATE TABLE ATHLETE_IMAGES (
	ATHLETE_ID INT REFERENCES ATHLETE (ATHLETE_ID) ON DELETE CASCADE,
	IMAGE_URL TEXT NOT NULL,
	PRIMARY KEY (ATHLETE_ID, IMAGE_URL)
);

-- Subtypes (Generalization)
CREATE TABLE AMATEUR (
	ATHLETE_ID INT PRIMARY KEY REFERENCES ATHLETE (ATHLETE_ID),
	CLUB_LOCATION VARCHAR (100) NOT NULL,
	TRAINING_CLUB VARCHAR(100) NOT NULL
);

CREATE TABLE PROFESSIONAL (
	ATHLETE_ID INT PRIMARY KEY REFERENCES ATHLETE (ATHLETE_ID)
);

-- Travel Stipend
CREATE TABLE TRAVEL_STIPEND (
	ATHLETE_ID INT UNIQUE REFERENCES ATHLETE (ATHLETE_ID) ON DELETE CASCADE,
	BASE_AMOUNT DECIMAL(10, 2) DEFAULT 0,
	BONUS DECIMAL(10, 2) DEFAULT 0,
	DATE DATE,
	PRIMARY KEY (ATHLETE_ID, DATE)
);

ALTER TABLE ATHLETE
ADD CONSTRAINT TSFK FOREIGN KEY (ATHLETE_ID, TSDATE) REFERENCES TRAVEL_STIPEND (ATHLETE_ID, DATE) DEFERRABLE INITIALLY DEFERRED;

-- Officials and Trials
CREATE TABLE OFFICIAL (
	OFFICIAL_ID INT PRIMARY KEY,
	NAME VARCHAR(100),
	EMAIL VARCHAR(100) UNIQUE,
	MOBILE VARCHAR(20),
	SPECIALTY VARCHAR(50),
	PERFORMANCE TEXT
);

CREATE TABLE TRIALS (
	TRIAL_ID INT PRIMARY KEY,
	TRIAL_TIME TIME NOT NULL,
	TRIAL_DATE DATE NOT NULL,
	PERFORMANCE_DATA TEXT NOT NULL
);

-- Many-to-Many: Athletes participate in Trials but at most one trials per athlete on any single day
CREATE TABLE PARTICIPATION (
	ATHLETE_ID INT REFERENCES ATHLETE (ATHLETE_ID),
	DATE DATE,
	TRIAL_ID INT,
	FOREIGN KEY (TRIAL_ID) REFERENCES TRIALS (TRIAL_ID),
	PRIMARY KEY (ATHLETE_ID, TRIAL_ID), -- fix
	UNIQUE (ATHLETE_ID, DATE) -- fix constraint for one trials per athlete on any single day
);

-- Many-to-Many: Officials participate in Trials
CREATE TABLE OVERSEES (
	OFFICIAL_ID INT REFERENCES OFFICIAL (OFFICIAL_ID),
	TRIAL_ID INT REFERENCES TRIALS (TRIAL_ID),
	PRIMARY KEY (OFFICIAL_ID, TRIAL_ID)
);

-- Equipment (No serial number used)
CREATE TABLE EQUIPMENT (
	AID INT REFERENCES ATHLETE ON DELETE CASCADE,
	MANUFACTURER VARCHAR(100),
	CONDITION_STATUS VARCHAR(9) NOT NULL,
	CONSTRAINT CHK_CONDITION_STATUS CHECK (
		CONDITION_STATUS IN ('poor', 'fair', 'good', 'very good', 'excellent')
	),
	NAME VARCHAR(100),
	MODEL VARCHAR(100),
	YEAR DATE,
	PRIMARY KEY (AID, NAME)
);

--SELECT EXTRACT(YEAR FROM year) FROM Equipment;
-- Sponsorships
CREATE TABLE SPONSORSHIP_PAYMENT (
	ATHLETE_ID INT REFERENCES ATHLETE (ATHLETE_ID) ON DELETE CASCADE,
	AMOUNT DECIMAL(10, 2),
	PAYMENT_DATE DATE,
	PAYMENT_TYPE VARCHAR(50) NOT NULL, -- e.g., 'Wire', 'Check', 'Credit'
	PRIMARY KEY (ATHLETE_ID, PAYMENT_DATE)
);

-- Medical Packages
CREATE TABLE MEDICAL_PACKAGE (
	PACKAGE_ID SERIAL PRIMARY KEY,
	PACKAGE_NAME VARCHAR(100),
	DESCRIPTION VARCHAR(100)
);

-- Junction table for Professional Medical Selection
CREATE TABLE PROFESSIONAL_MEDICAL_SELECTION (
	ATHLETE_ID INT REFERENCES PROFESSIONAL (ATHLETE_ID),
	PACKAGE_ID INT REFERENCES MEDICAL_PACKAGE (PACKAGE_ID),
	PRIMARY KEY (ATHLETE_ID, PACKAGE_ID)
);

CREATE OR REPLACE FUNCTION enforce_minimum_medical_package_limits()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    pkg_count INTEGER;
BEGIN
    --------------------------------------------------------------------
    -- AFTER INSERT on Professional: must have at least 1 package
    --------------------------------------------------------------------
        SELECT COUNT(*)
        INTO pkg_count
        FROM Professional_Medical_Selection
        WHERE athlete_id = NEW.athlete_id;

        IF pkg_count < 1 THEN
            RAISE EXCEPTION
                'Professional % must have at least one medical package.',
                NEW.athlete_id;
        END IF;
        RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_professional_min_package
AFTER INSERT ON Professional
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION enforce_minimum_medical_package_limits();

-- Check constraint to enforce "each professional may have up to 5 medical packages." WE USE STORED PROCEDURES.
DROP FUNCTION limit_medical_packages() CASCADE;
CREATE OR REPLACE FUNCTION limit_medical_packages()
RETURNS BOOLEAN
LANGUAGE plpgsql AS $$
BEGIN
   IF NOT EXISTS (SELECT athlete_id FROM Professional NATURAL JOIN Professional_Medical_Selection GROUP BY athlete_id HAVING ((COUNT(athlete_id) > 4))) THEN
       PERFORM 'Professional exceeds 5 medical packages.';
           RETURN TRUE;
    ELSE
    RETURN FALSE;
	END IF;
END;
$$;
ALTER TABLE Professional_Medical_Selection ADD CONSTRAINT CHECK_LIMIT_MEDICAL_PACKAGES CHECK(limit_medical_packages());



-- select * from Professional_Medical_Selection;
-- Check constraint to enforce total participation between Athlete and Participates
CREATE
OR REPLACE FUNCTION CHECK_ATHLETE_PARTICIPATION () RETURNS TRIGGER AS $$
BEGIN
    -- Check if the athlete exists in the Participation table
    IF NOT EXISTS (
        SELECT 1 FROM Participation WHERE athlete_id = NEW.athlete_id
    ) THEN
        RAISE EXCEPTION 'Total Participation Violated: Athlete % must be associated with a Trials.', NEW.athlete_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE CONSTRAINT TRIGGER TRIGGER_CHECK_ATHLETE_PARTICIPATION
AFTER INSERT ON ATHLETE DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION CHECK_ATHLETE_PARTICIPATION ();

-- Check constraint to enforce total participation between Trials and Participates
CREATE
OR REPLACE FUNCTION CHECK_TRIALS_PARTICIPATION () RETURNS TRIGGER AS $$
BEGIN
    -- Check if the athlete exists in the Participation table
    IF NOT EXISTS (
        SELECT 1 FROM Participation WHERE trial_id = NEW.trial_id
    ) THEN
        RAISE EXCEPTION 'Total Participation Violated: A trial % must be associated with athletes.', NEW.trial_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- 2. Create a CONSTRAINT TRIGGER
-- This MUST be "AFTER INSERT" and "DEFERRABLE" to allow you to 
-- insert the Athlete and Participation in the same transaction.
CREATE CONSTRAINT TRIGGER TRIGGER_TOTAL_PARTICIPATION_TRIALS
AFTER INSERT ON TRIALS DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION CHECK_TRIALS_PARTICIPATION ();

-- Check constraint to enforce total participation between Trials and Oversees
CREATE
OR REPLACE FUNCTION CHECK_TRIALS_OVERSEES () RETURNS TRIGGER AS $$
BEGIN
    -- Check if the athlete exists in the Participation table
    IF NOT EXISTS (
        SELECT 1 FROM Oversees WHERE trial_id = NEW.trial_id
    ) THEN
        RAISE EXCEPTION 'Total Participation Violated: A trial % must be associated with athletes.', NEW.trial_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- 2. Create a CONSTRAINT TRIGGER
-- This MUST be "AFTER INSERT" and "DEFERRABLE" to allow you to 
-- insert the Trials and Oversees in the same transaction.
CREATE CONSTRAINT TRIGGER TRIGGER_TOTAL_PARTICIPATION_TRIALSOVERSEES
AFTER INSERT ON TRIALS DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION CHECK_TRIALS_OVERSEES ();

-- Check constraint to enforce total participation between Officials and Oversees
CREATE
OR REPLACE FUNCTION CHECK_OFFICIALS_OVERSEES () RETURNS TRIGGER AS $$
BEGIN
    -- Check if the athlete exists in the Participation table
    IF NOT EXISTS (
        SELECT 1 FROM Oversees WHERE official_id = NEW.official_id
    ) THEN
        RAISE EXCEPTION 'Total Participation Violated: Every offical % must be associated with a trial.', NEW.official_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- 2. Create a CONSTRAINT TRIGGER
-- This MUST be "AFTER INSERT" and "DEFERRABLE" to allow you to 
-- insert the Officials and Oversees in the same transaction.
-- Check constraint to enforce total and disjoint constraints on Athele IsA
CREATE CONSTRAINT TRIGGER TRIGGER_TOTAL_PARTICIPATION_OFFICIALSOVERSEES
AFTER INSERT ON OFFICIAL DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION CHECK_OFFICIALS_OVERSEES ();

-- Check constraint to enforce total and disjoint constraints on Athele IsA
CREATE
OR REPLACE FUNCTION CHECK_ATHLETEISA () RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ 
BEGIN 
IF EXISTS (
        SELECT athlete_id FROM Athlete
        EXCEPT
        (SELECT athlete_id FROM Amateur UNION SELECT athlete_id FROM Professional)
    ) THEN 
        RAISE EXCEPTION 'Total Participation Violated: Some athletes are neither Amateur nor Professional';
    END IF;

-- 2. Check for Disjoint Participation (Is an athlete in BOTH?)
    IF EXISTS (
        SELECT athlete_id FROM Amateur
        INTERSECT
        SELECT athlete_id FROM Professional
    ) THEN 
        RAISE EXCEPTION 'Disjoint Participation Violated: An athlete cannot be both Amateur and Professional';
    END IF;
RETURN NEW;
END $$;

-- 2. Create a CONSTRAINT TRIGGER
-- This MUST be "AFTER INSERT" and "DEFERRABLE" to allow you to 
-- insert the Athlete, Amateur, and Professional in the same transaction.
CREATE CONSTRAINT TRIGGER TOTAL_DISJOINT_PARTICIPATION_ISA
AFTER INSERT ON ATHLETE DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION CHECK_ATHLETEISA ();

-- 2. Create a CONSTRAINT TRIGGER
-- This MUST be "AFTER INSERT" and "DEFERRABLE" to allow you to 
-- insert the Athlete, Amateur, and Professional in the same transaction.
CREATE CONSTRAINT TRIGGER TOTAL_DISJOINT_PARTICIPATION_ISA
AFTER INSERT ON AMATEUR DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION CHECK_ATHLETEISA ();

-- ============================ -- 1. ATHLETES -- ============================ 
BEGIN;

INSERT INTO
	ATHLETE (
		ATHLETE_ID,
		FIRSTNAME,
		LASTNAME,
		DOB,
		HEIGHT,
		WEIGHT,
		NATIONALITY,
		EMAIL,
		PASSPORT_NUMBER,
		MOBILE_NUMBER,
		TSDATE,
		BIO
	)
VALUES
	(
		1,
		'Alice',
		'Runner',
		'1998-04-12',
		170.00,
		60.00,
		'Australia',
		'alice@example.com',
		10001,
		410000001,
		'2024-01-01',
		'Sprinter'
	),
	(
		2,
		'Bob',
		'Swimmer',
		'1995-09-20',
		185.00,
		78.00,
		'USA',
		'bob@example.com',
		10002,
		410000002,
		'2024-01-01',
		'Freestyle swimmer'
	),
	(
		3,
		'Carlos',
		'Boxer',
		'1992-02-10',
		178.00,
		82.00,
		'Spain',
		'carlos@example.com',
		10003,
		410000003,
		'2024-01-01',
		'Lightweight boxer'
	);

-- ============================ -- 2. TRAVEL STIPENDS (must match tsdate) -- ============================ 
INSERT INTO
	TRAVEL_STIPEND (ATHLETE_ID, BASE_AMOUNT, BONUS, DATE)
VALUES
	(1, 500, 50, '2024-01-01'),
	(2, 600, 75, '2024-01-01'),
	(3, 550, 60, '2024-01-01');

-- ============================ -- 3. ATHLETE SUBTYPES (total + disjoint) -- ============================ 
INSERT INTO
	AMATEUR (ATHLETE_ID, TRAINING_CLUB, CLUB_LOCATION)
VALUES
	(1, 'Sydney Track Club', 'SYDNEY');

INSERT INTO
	PROFESSIONAL (ATHLETE_ID)
VALUES
	(2),
	(3);

INSERT INTO
	TRIALS (
		TRIAL_ID,
		TRIAL_DATE,
		TRIAL_TIME,
		PERFORMANCE_DATA
	)
VALUES
	(10, '2024-02-01', '10:15:00', '100m sprint'),
	(11, '2024-02-03', '12:15:00', 'Swimming 200m'),
	(12, '2024-02-02', '14:15:00', 'Boxing qualifier');

INSERT INTO
	OFFICIAL (
		OFFICIAL_ID,
		NAME,
		EMAIL,
		MOBILE,
		SPECIALTY,
		PERFORMANCE
	)
VALUES
	(
		100,
		'Ref One',
		'ref1@example.com',
		'0400000001',
		'Track',
		'Excellent'
	),
	(
		101,
		'Ref Two',
		'ref2@example.com',
		'0400000002',
		'Swimming',
		'Very Good'
	),
	(
		102,
		'Ref Three',
		'ref3@example.com',
		'0400000003',
		'Boxing',
		'Fair'
	);

INSERT INTO
	OVERSEES (OFFICIAL_ID, TRIAL_ID)
VALUES
	(100, 10),
	(101, 11),
	(102, 12);

INSERT INTO
	PARTICIPATION (ATHLETE_ID, TRIAL_ID, DATE)
VALUES
	(1, 10, '2024-02-01'),
	(2, 11, '2024-02-03'),
	(3, 12, '2024-02-02');
--END;

--BEGIN;

-- ============================ -- 8. MEDICAL PACKAGES -- ============================ 
INSERT INTO MEDICAL_PACKAGE (PACKAGE_ID, PACKAGE_NAME, DESCRIPTION) VALUES
    (1, 'Basic Physio', 'Initial assessment and foundational mobility exercises for injury recovery.'),
    (2, 'Advanced Rehab', 'Post-operative recovery focused on intensive muscle strengthening and joint stability.'),
    (3, 'Nutrition Plan', 'Customized dietary guidance tailored to metabolic health and fitness goals.'),
    (4, 'Strength Program', 'Resistance training protocols designed to increase bone density and lean mass.'),
    (5, 'Cardio Program', 'Endurance-based routines focused on heart health and respiratory efficiency.'),
    (6, 'Intermediate', 'A balanced transition program combining mobility, strength, and aerobic conditioning.');

-- ============================ -- 9. PROFESSIONAL MEDICAL SELECTION -- (each professional must have 1–5 packages) -- ============================ I
INSERT INTO
	PROFESSIONAL_MEDICAL_SELECTION (ATHLETE_ID, PACKAGE_ID)
VALUES
	(2, 1),
	(2, 2),
	(3, 1),
	(3, 3),
	(3, 4);

-- ============================ -- 10. ATHLETE IMAGES (optional but valid) -- ============================ 
INSERT INTO
	ATHLETE_IMAGES (ATHLETE_ID, IMAGE_URL)
VALUES
	(1, 'http://example.com/alice1.jpg'),
	(2, 'http://example.com/bob1.jpg'),
	(3, 'http://example.com/carlos1.jpg');

-- ============================ -- 11. EQUIPMENT (optional but valid) -- ============================ 
INSERT INTO
	EQUIPMENT (
		AID,
		MANUFACTURER,
		CONDITION_STATUS,
		NAME,
		MODEL,
		YEAR
	)
VALUES
	(
		1,
		'Nike',
		'good',
		'Running Shoes',
		'ZoomX',
		'2023-01-01'
	),
	(
		2,
		'Speedo',
		'excellent',
		'Swim Goggles',
		'AquaPro',
		'2022-01-01'
	),
	(
		3,
		'Everlast',
		'very good',
		'Gloves',
		'Elite',
		'2021-01-01'
	);

-- ============================ -- 12. SPONSORSHIP PAYMENTS (optional but valid) -- ============================ 
INSERT INTO
	SPONSORSHIP_PAYMENT (ATHLETE_ID, AMOUNT, PAYMENT_DATE, PAYMENT_TYPE)
VALUES
	(1, 2000, '2024-03-01', 'Wire'),
	(2, 2500, '2024-03-01', 'Credit'),
	(3, 1800, '2024-03-01', 'Check');

END;

-- 1. BREAK IsA TOTAL PARTICIPATION -- Athlete inserted but NOT added to Amateur or Professional ------------------------------------------------------------ 
BEGIN;

INSERT INTO
	ATHLETE (
		ATHLETE_ID,
		FIRSTNAME,
		LASTNAME,
		DOB,
		HEIGHT,
		WEIGHT,
		NATIONALITY,
		EMAIL,
		PASSPORT_NUMBER,
		MOBILE_NUMBER,
		TSDATE,
		BIO
	)
VALUES
	(
		50,
		'IsA',
		'Breaker',
		'2000-01-01',
		180.00,
		70.00,
		'Nowhere',
		'isa.breaker@email.com',
		99999,
		5550100,
		'2024-01-01',
		'TBA'
	);

INSERT INTO
	TRAVEL_STIPEND (ATHLETE_ID, BASE_AMOUNT, BONUS, DATE)
VALUES
	(50, 100, 10, '2024-01-01');

--total_disjoint_participation_isa: Athlete must appear in Amateur or Professional ------------------------------------------------------------ ------------------------------------------------------------ 
END;

-- 2. BREAK PROFESSIONAL MEDICAL PACKAGE LIMIT (>5) ------------------------------------------------------------ 
-- Ensure athlete 2 is a Professional 
BEGIN;
INSERT INTO
	PROFESSIONAL (ATHLETE_ID)
VALUES (2) ON CONFLICT DO NOTHING;
select * from PROFESSIONAL_MEDICAL_SELECTION;
-- Insert 6 packages → violates limit of 5 
INSERT INTO
	 PROFESSIONAL_MEDICAL_SELECTION(ATHLETE_ID, PACKAGE_ID)
VALUES
	(2, 3),
	(2, 4),
	(2, 5),
	(2, 6);
END;
-- This one triggers the violation -- EXPECTED ERROR: -- ERROR: limit of medical packages Violated. ------------------------------------------------------------ ------------------------------------------------------------ 

-- 3. BREAK ATHLETE PARTICIPATION (Athlete with no Participation) ------------------------------------------------------------
BEGIN;
INSERT INTO
	ATHLETE (
		ATHLETE_ID,
		FIRSTNAME,
		LASTNAME,
		DOB,
		HEIGHT,
		WEIGHT,
		NATIONALITY,
		EMAIL,
		PASSPORT_NUMBER,
		MOBILE_NUMBER,
		TSDATE,
		BIO
	)
VALUES
	(
		60,
		'No Participation',
		'Athlete',
		'1999-05-05',
		175,
		65,
		'UK',
		'none@example.com',
		0,
		0,
		'2024-01-01',
		'Will fail'
	);

INSERT INTO
	TRAVEL_STIPEND (ATHLETE_ID, BASE_AMOUNT, BONUS, DATE)
VALUES
	(60, 100, 10, '2024-01-01');

--------------------- ------------------------------------------------------------ 
END;

BEGIN;

INSERT INTO
	ATHLETE (
		ATHLETE_ID,
		FIRSTNAME,
		LASTNAME,
		DOB,
		HEIGHT,
		WEIGHT,
		NATIONALITY,
		EMAIL,
		PASSPORT_NUMBER,
		MOBILE_NUMBER,
		TSDATE,
		BIO
	)
VALUES
	(
		60,
		'No Participation',
		'Athlete',
		'1999-05-05',
		175,
		65,
		'UK',
		'none@example.com',
		0,
		0,
		'2024-01-01',
		'Will fail'
	);

INSERT INTO
	TRAVEL_STIPEND (ATHLETE_ID, BASE_AMOUNT, BONUS, DATE)
VALUES
	(60, 100, 10, '2024-01-01');

--total_disjoint_participation_isa: Athlete must appear in Amateur or Professional ------------------------------------------------------------ ------------------------------------------------------------ 
INSERT INTO
	AMATEUR (ATHLETE_ID, TRAINING_CLUB, CLUB_LOCATION)
VALUES
	(60, 'London Club', 'London');

-- EXPECTED ERROR: -- ERROR: Total Participation Violated: Athlete 60 must be associated with a Trial. ------------------------------------------------------------ ------------------------------------------------------------ 
INSERT INTO
	PARTICIPATION (ATHLETE_ID, TRIAL_ID, DATE)
VALUES
	(61, 10, '2024-02-01');

END;

-- EXPECTED ERROR: -- ERROR: Total Participation Violated: Athlete 60 must be associated with a Trial. ------------------------------------------------------------ ------------------------------------------------------------ 
-- 4. BREAK TRIAL PARTICIPATION (Trial with no Athletes) ------------------------------------------------------------ 
INSERT INTO
	TRIALS (
		TRIAL_ID,
		TRIAL_DATE,
		TRIAL_TIME,
		PERFORMANCE_DATA
	)
VALUES
	(99, '2024-01-01', '15:00', 'Empty trial');

-- EXPECTED ERROR (after transaction ends): -- ERROR: Total Participation Violated: A trial 99 must be associated with athletes. ------------------------------------------------------------ ------------------------------------------------------------ 
-- 5. BREAK TRIAL–OFFICIAL PARTICIPATION (Trial with no Officials) ------------------------------------------------------------ 

INSERT INTO
	TRIALS (
		TRIAL_ID,
		TRIAL_DATE,
		TRIAL_TIME,
		PERFORMANCE_DATA
	)
VALUES
	(98, '2024-01-01', '16:00', 'No officials');

-- EXPECTED ERROR (after transaction ends): -- ERROR: Total Participation Violated: A trial 98 must be associated with athletes. -- (Your trigger message incorrectly says "athletes" even though it's checking officials.) ------------------------------------------------------------ ------------------------------------------------------------ 
-- 6. BREAK OFFICIALS TOTAL PARTICIPATION (Official with no Oversees) ------------------------------------------------------------ 

INSERT INTO
	OFFICIAL (
		OFFICIAL_ID,
		NAME,
		EMAIL,
		MOBILE,
		SPECIALTY,
		PERFORMANCE
	)
VALUES
	(
		500,
		'Lonely Ref',
		'lonely@example.com',
		'0400000999',
		'None',
		'OK'
	);

-- EXPECTED ERROR (after transaction ends): -- ERROR: Total Participation Violated: A trial 500 must be associated with athletes. 
------------------------------------------------------------ ------------------------------------------------------------ 
-- 7. BREAK EQUIPMENT CHECK CONSTRAINT ------------------------------------------------------------ 

INSERT INTO
	EQUIPMENT (
		AID,
		MANUFACTURER,
		CONDITION_STATUS,
		NAME,
		MODEL,
		YEAR
	)
VALUES
	(
		1,
		'BadBrand',
		'terrible',
		'Broken Gear',
		'X1',
		'2020-01-01'
	);

-- EXPECTED ERROR: -- ERROR: new row for relation "equipment" violates check constraint "chk_condition_status" ------------------------------------------------------------ ------------------------------------------------------------ 
-- 8. BREAK TRAVEL STIPEND FK (tsdate mismatch) ------------------------------------------------------------ 

INSERT INTO
	ATHLETE (
		ATHLETE_ID,
		FIRSTNAME,
		LASTNAME,
		DOB,
		HEIGHT,
		WEIGHT,
		NATIONALITY,
		EMAIL,
		PASSPORT_NUMBER,
		MOBILE_NUMBER,
		TSDATE,
		BIO
	)
VALUES
	(
		70,
		'TS',
		'Mismatch',
		'1990-01-01',
		180,
		80,
		'USA',
		'none@example.com',
		0,
		0,
		'2024-02-01',
		'Will fail'
	);

INSERT INTO
	TRAVEL_STIPEND (ATHLETE_ID, BASE_AMOUNT, BONUS, DATE)
VALUES
	(70, 300, 30, '2024-01-01');

-- EXPECTED ERROR: -- ERROR: insert or update on table "athlete" violates foreign key constraint "tsfk" 

------------------------------------------------------------ ------------------------------------------------------------ 
-- 9. BREAK PARTICIPATION PRIMARY KEY (duplicate key) ------------------------------------------------------------ 

INSERT INTO
	PARTICIPATION (ATHLETE_ID, TRIAL_ID, DATE)
VALUES
	(1, 10, '2024-02-01');


-- Duplicate PK if already exists -- EXPECTED ERROR: -- ERROR: duplicate key value violates unique constraint "participation_pkey"