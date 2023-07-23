--
-- PostgreSQL database dump
--

-- Dumped from database version 15.1
-- Dumped by pg_dump version 15.1 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: add_reservation_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_reservation_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO Reservation (src_date, train_no, coach_no, coach_type, seat_no, station, is_booked, seat_type)
  SELECT
    current_timestamp,
    NEW.train_no,
    'C1',
    '3AC',
    ROW_NUMBER() OVER (),
    NEW.stn_id,
    'N',
    'W'
  FROM generate_series(1, 4)
  WHERE NOT EXISTS (
    SELECT 1 FROM Reservation
    WHERE src_date = current_timestamp AND train_no = NEW.train_no AND station = NEW.stn_id
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.add_reservation_trigger() OWNER TO postgres;

--
-- Name: cancel_seat(integer, integer, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.cancel_seat(IN pnr_no_ integer, IN usr_id integer, IN pass_ids text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    rec_stBtw record;
    rec_pass record;
    bkng_no INTEGER;
    totalFare INTEGER;
    trxn_id_ INTEGER;
    pass_ids_arr INTEGER[];
    src_ VARCHAR(4);
    dst_ VARCHAR(4);
    coach_no_ VARCHAR(4);
    seat_no_ INTEGER;
    tno_ INTEGER;
    DOJ TIMESTAMP;
BEGIN
    -- Convert the comma-separated string to an array
    pass_ids_arr := string_to_array(pass_ids, ',');

    IF ((SELECT count(*) FROM pass_tkt where pnr_no=pnr_no_) = 0) THEN
        RAISE NOTICE 'No such booking found with specified pnr number';
        RETURN;
    END IF;
    -- fetching booking number, trxn_id, tno_
    SELECT booking_id INTO bkng_no FROM pass_tkt where pnr_no=pnr_no_;
    -- RAISE NOTICE 'bkng_no (%)', bkng_no;

    SELECT MAX(txn_id) INTO trxn_id_ FROM Booking where booking_id=bkng_no;        --select highest txn id; multiple part-cancellations allowed
    -- RAISE NOTICE 'MAX(txn_id) (%)', trxn_id_;
    
    SELECT train_no INTO tno_ FROM pass_tkt where pnr_no=pnr_no_;
    -- RAISE NOTICE 'tno_ (%)', tno_;

    SELECT src_date INTO DOJ FROM pass_tkt where pnr_no=pnr_no_;
    -- RAISE NOTICE 'DOJ (%)', DOJ;

    totalFare := 0;       -- base fare not to be refunded

    -- for each passenger who wish to be cancelled
    FOR rec_pass IN SELECT unnest(pass_ids_arr) AS passr_id LOOP
        -- getting src dst for that pass; general case
        SELECT src INTO src_ FROM pass_tkt where pnr_no=pnr_no_ AND pass_id=rec_pass.passr_id;
        SELECT dest INTO dst_ FROM pass_tkt where pnr_no=pnr_no_ AND pass_id=rec_pass.passr_id;
        SELECT coach_no INTO coach_no_ FROM pass_tkt where pnr_no=pnr_no_ AND pass_id=rec_pass.passr_id;
        SELECT seat_no INTO seat_no_ FROM pass_tkt where pnr_no=pnr_no_ AND pass_id=rec_pass.passr_id;

        UPDATE pass_tkt SET "isConfirmed"='CAN' WHERE pnr_no=pnr_no_ AND pass_id=rec_pass.passr_id;
        totalFare := totalFare + (SELECT count(*) FROM station_between(tno_,src_,dst_))*25 + 0;

        -- mark the seat unbooked for the entire duration (except dest) in Reservation table
        FOR rec_stBtw IN SELECT * FROM station_between(tno_,src_,dst_) WHERE station_id != dst_ LOOP
            UPDATE Reservation
            SET is_booked='N' WHERE src_date=DOJ AND train_no=tno_ AND coach_no=coach_no_ AND seat_no=seat_no_ AND station=rec_stBtw.station_id;
        END LOOP;
        RAISE NOTICE 'cancelled pass_id = %', (rec_pass.passr_id);
    END LOOP;

    totalFare := totalFare * -1;

    -- add to booking table
    INSERT INTO Booking ("booking_id","fare","txn_id","user_id","booking_date")
    VALUES
    (bkng_no,totalFare,(trxn_id_*2)+1,usr_id,NOW());
    RAISE NOTICE 'refund ₹%', (-1*totalFare);

END;
$$;


ALTER PROCEDURE public.cancel_seat(IN pnr_no_ integer, IN usr_id integer, IN pass_ids text) OWNER TO postgres;

--
-- Name: cancel_ticket(integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.cancel_ticket(IN p_pnr_no integer, IN p_pass_id integer)
    LANGUAGE plpgsql
    AS $$
declare
    v_train_no INTEGER;
    v_src VARCHAR(4);
    v_dest VARCHAR(4);
    v_coach_no VARCHAR(5);
    v_seat_no INTEGER;
    v_curr_stn VARCHAR(4);
    v_next_stn VARCHAR(4);
BEGIN
    -- Get the train number, source station, and destination station for the given PNR number
    SELECT train_no, src, dest INTO v_train_no, v_src, v_dest
    FROM pass_tkt
    WHERE pnr_no = p_pnr_no AND pass_id = p_pass_id;

    -- Get the coach number and seat number for the given PNR number
    SELECT coach_no, seat_no INTO v_coach_no, v_seat_no
    FROM Reservation
    WHERE train_no = v_train_no AND is_booked = 'Y' AND seat_no IN (
        SELECT seat_no
        FROM pass_tkt
        WHERE pnr_no = p_pnr_no AND pass_id = p_pass_id
    );

    -- Update the Reservation table to mark the seat as unbooked
    UPDATE Reservation
    SET is_booked = 'N'
    WHERE train_no = v_train_no AND coach_no = v_coach_no AND seat_no = v_seat_no;

    -- Update the Seat_Status table to mark the seat as available
    UPDATE Seat_Status
    SET occupancy_status = 'AVAILABLE', current_pass_id = NULL, current_pnr_no = NULL
    WHERE train_no = v_train_no AND coach_no = v_coach_no AND seat_no = v_seat_no;

    -- Check if there is a next station after the source station
    SELECT stn_id INTO v_curr_stn
    FROM Schedule
    WHERE train_no = v_train_no AND stn_id = v_src;

    SELECT stn_id INTO v_next_stn
    FROM Schedule
    WHERE train_no = v_train_no AND Dayofjny = (
        SELECT Dayofjny
        FROM Schedule
        WHERE train_no = v_train_no AND stn_id = v_src
    ) AND arr_time > (
        SELECT arr_time
        FROM Schedule
        WHERE train_no = v_train_no AND stn_id = v_src
    )
    ORDER BY arr_time
    FETCH FIRST 1 ROW ONLY;

    -- If there is a next station, update the Seat_Status table to mark the seat between the current and next stations as available
    IF v_next_stn IS NOT NULL THEN
        UPDATE Seat_Status
        SET occupancy_status = 'AVAILABLE'
        WHERE train_no = v_train_no AND coach_no = v_coach_no AND seat_no IN (
            SELECT seat_no
            FROM Reservation
            WHERE train_no = v_train_no AND is_booked = 'N' AND coach_no = v_coach_no AND seat_no IN (
                SELECT seat_no
                FROM Schedule
                WHERE train_no = v_train_no AND stn_id = v_next_stn
            )
        );
    END IF;
END $$;


ALTER PROCEDURE public.cancel_ticket(IN p_pnr_no integer, IN p_pass_id integer) OWNER TO postgres;

--
-- Name: delete_passenger_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_passenger_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM passenger WHERE user_id = OLD.user_id;
  END IF;
  RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_passenger_trigger() OWNER TO postgres;

--
-- Name: num_available(integer, character varying, character varying, timestamp without time zone, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.num_available(tno integer, src character varying, dst character varying, doj timestamp without time zone, c_typ character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
cnt INTEGER;
rec_res record;
rec_stBtw record;
rec record;
flag BOOLEAN;
BEGIN
    cnt := 0;
    FOR rec_res in SELECT DISTINCT coach_no AS coach_no_,seat_no AS seat_no_ FROM Reservation WHERE src_date=DOJ AND train_no=tno AND coach_type=c_typ LOOP
        flag := false;
        IF (SELECT count(*) FROM station_between(tno,src,dst) WHERE station_id != dst)=0 THEN
            flag := true;
        END IF;
        FOR rec_stBtw in SELECT * FROM station_between(tno,src,dst) WHERE station_id != dst LOOP
            IF (SELECT is_booked FROM Reservation WHERE src_date=DOJ AND train_no=tno AND coach_no=rec_res.coach_no_ AND seat_no=rec_res.seat_no_ AND station=rec_stBtw.station_id)='Y' THEN
                flag := true;
            END IF;
        END LOOP;
        IF flag=false THEN
            cnt := cnt+1;
        END IF;
    END LOOP;
    return cnt;
END;
$$;


ALTER FUNCTION public.num_available(tno integer, src character varying, dst character varying, doj timestamp without time zone, c_typ character varying) OWNER TO postgres;

--
-- Name: reserve_seat(integer, character varying, character varying, timestamp without time zone, character varying, integer, integer, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.reserve_seat(IN tno integer, IN src character varying, IN dst character varying, IN doj timestamp without time zone, IN c_typ character varying, IN usr_id integer, IN trxn_id integer, IN pass_ids text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    rec_res record;
    rec_stBtw record;
    rec_pass record;
    flag BOOLEAN;
    pnr_no_ INTEGER;
    bkng_no INTEGER;
    totalFare INTEGER;
    pass_ids_arr INTEGER[];
BEGIN
    -- Convert the comma-separated string to an array
    pass_ids_arr := string_to_array(pass_ids, ',');

    IF (SELECT num_available(tno,src,dst,doj,c_typ)) < array_length(pass_ids_arr, 1) THEN
        RAISE NOTICE 'Not enough seats available';
        RETURN;
    END IF;

    -- generating pnr number and booking number
    SELECT count(*) INTO pnr_no_ FROM pass_tkt;
    pnr_no_ := pnr_no_ + 56734512;
    SELECT count(*) INTO bkng_no FROM Booking;
    bkng_no := bkng_no + 73772234;

    -- for each passenger
    FOR rec_pass IN SELECT unnest(pass_ids_arr) AS passr_id LOOP
        FOR rec_res IN SELECT DISTINCT coach_no AS coach_no_,seat_no AS seat_no_ FROM Reservation WHERE src_date=DOJ AND train_no=tno AND coach_type=c_typ LOOP
            flag := false;
            FOR rec_stBtw IN SELECT * FROM station_between(tno,src,dst) WHERE station_id != dst LOOP
                IF (SELECT is_booked FROM Reservation WHERE src_date=DOJ AND train_no=tno AND coach_no=rec_res.coach_no_ AND seat_no=rec_res.seat_no_ AND station=rec_stBtw.station_id)='Y' THEN
                    flag := true;
                END IF;
            END LOOP;

            -- when a suitable seat is found
            IF flag=false THEN
                -- INITIATE BOOKING PROCESS for the passenger 

                -- mark the seat booked for the entire duration (except dest) in Reservation table
                FOR rec_stBtw IN SELECT * FROM station_between(tno,src,dst) WHERE station_id != dst LOOP
                    UPDATE Reservation
                    SET is_booked='Y' WHERE src_date=DOJ AND train_no=tno AND coach_no=rec_res.coach_no_ AND seat_no=rec_res.seat_no_ AND station=rec_stBtw.station_id;
                END LOOP;

                -- add to pass_tkt table
                INSERT INTO pass_tkt ("pnr_no","src_date","pass_id","booking_id","train_no","coach_no","seat_no","food_order_id","src","dest","isConfirmed")
                VALUES
                (pnr_no_,doj,rec_pass.passr_id,bkng_no,tno,rec_res.coach_no_,rec_res.seat_no_,NULL,src,dst,'CNF');


                EXIT;
                -- BOOKING DONE
            END IF;
        END LOOP;
    END LOOP;

    totalFare := 35 + array_length(pass_ids_arr, 1)*(SELECT count(*) FROM station_between(tno,src,dst))*30 + 0;

    -- add to booking table
    INSERT INTO Booking ("booking_id","fare","txn_id","user_id","booking_date")
    VALUES
    (bkng_no,totalFare,trxn_id,usr_id,NOW());

END;
$$;


ALTER PROCEDURE public.reserve_seat(IN tno integer, IN src character varying, IN dst character varying, IN doj timestamp without time zone, IN c_typ character varying, IN usr_id integer, IN trxn_id integer, IN pass_ids text) OWNER TO postgres;

--
-- Name: station_between(integer, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.station_between(p_train_no integer, p_start_stn character varying, p_end_stn character varying) RETURNS TABLE(station_id character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT stn_id
    FROM Schedule
    WHERE train_no = p_train_no 
    AND (
            ( -- single day travel
                (
                    (
                        SELECT "Dayofjny"
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_start_stn
                    )
                    =
                    (
                        SELECT "Dayofjny"
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_end_stn
                    )
                ) AND (
                    "Dayofjny" = (
                        SELECT "Dayofjny"
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_start_stn
                    )
                ) AND (
                    dep_time >= (
                        SELECT dep_time
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_start_stn
                    )
                ) AND (
                    arr_time <= (
                        SELECT arr_time
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_end_stn
                    )
                )
)
            OR
            ( -- multi day travel
                (
                    (
                        SELECT "Dayofjny"
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_start_stn
                    )
                    <
                    (
                        SELECT "Dayofjny"
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_end_stn
                    )
                ) AND 
                (
                    ( -- first doj
                        (
                            "Dayofjny" = (
                                SELECT "Dayofjny"
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_start_stn
                            )
                        ) AND (
                            dep_time >= (
                                SELECT dep_time
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_start_stn
                            )
                        )
                    )
OR
                    ( -- last doj
                        (
                            "Dayofjny" = (
                                SELECT "Dayofjny"
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_end_stn
                            )
                        ) AND (
                            arr_time <= (
                                SELECT arr_time
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_end_stn
                            )
                        )
                    )
                    OR
                    ( -- intermediate doj
                        (
                            "Dayofjny" > (
                                SELECT "Dayofjny"
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_start_stn
                            )
                        ) AND (
                            "Dayofjny" < (
                                SELECT "Dayofjny"
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_end_stn
                            )
                        )
                    )
                )
            )
        )
    ORDER BY "Dayofjny",dep_time;
END;
$$;


ALTER FUNCTION public.station_between(p_train_no integer, p_start_stn character varying, p_end_stn character varying) OWNER TO postgres;

--
-- Name: trainsbtwstns(character varying, character varying, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trainsbtwstns(src_id character varying, dst_id character varying, day integer) RETURNS TABLE(train_no integer, src_stn_id character varying, dest_stn_id character varying, days_of_wk integer, src_arr_time time without time zone, src_dep_time time without time zone, dest_arr_time time without time zone, dest_dep_time time without time zone, daynum integer)
    LANGUAGE plpgsql
    AS $$
-- declare 
-- variable declaration
begin
RETURN QUERY
SELECT s1.train_no,s1.stn_id,s2.stn_id,s1.days_of_wk,s1.arr_time,s1.dep_time,s2.arr_time,s2.dep_time,s2."Dayofjny"-s1."Dayofjny" FROM Schedule as s1 cross join Schedule as s2 where (s1.days_of_wk&(1<<day))>0 and s1.train_no=s2.train_no and s1.stn_id=src_id and s2.stn_id=dst_id and (s1."Dayofjny"<s2."Dayofjny" or (s1."Dayofjny"=s2."Dayofjny" and s1.dep_time<s2.arr_time));
end; $$;


ALTER FUNCTION public.trainsbtwstns(src_id character varying, dst_id character varying, day integer) OWNER TO postgres;

--
-- Name: update_pass_tkt_status_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_pass_tkt_status_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.is_booked = 'N' THEN
      UPDATE pass_tkt
      SET isConfirmed = 'CAN'
      WHERE pnr_no = NEW.pnr_no AND pass_id = NEW.pass_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_pass_tkt_status_trigger() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: booking; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.booking (
    booking_id integer NOT NULL,
    fare integer NOT NULL,
    txn_id integer NOT NULL,
    user_id integer,
    booking_date timestamp without time zone
);


ALTER TABLE public.booking OWNER TO postgres;

--
-- Name: pass_tkt; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pass_tkt (
    pnr_no integer NOT NULL,
    src_date timestamp without time zone,
    pass_id integer NOT NULL,
    booking_id integer NOT NULL,
    train_no integer NOT NULL,
    coach_no character varying(5),
    seat_no integer,
    food_order_id integer,
    src character varying(4) NOT NULL,
    dest character varying(4) NOT NULL,
    "isConfirmed" character varying(3) NOT NULL,
    CONSTRAINT "pass_tkt_isConfirmed_check" CHECK ((("isConfirmed")::text = ANY ((ARRAY['CNF'::character varying, 'WL'::character varying, 'RAC'::character varying, 'CAN'::character varying])::text[])))
);


ALTER TABLE public.pass_tkt OWNER TO postgres;

--
-- Name: passenger; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.passenger (
    pass_id integer NOT NULL,
    name character varying(20),
    age integer,
    gender character varying(5),
    nationality character varying(20),
    concsn_type character varying(20),
    user_id integer,
    CONSTRAINT passenger_age_check CHECK ((age >= 0)),
    CONSTRAINT passenger_concsn_type_check CHECK (((concsn_type)::text = ANY ((ARRAY['senior_ctzn'::character varying, 'armed_forces'::character varying, 'student'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT passenger_gender_check CHECK (((gender)::text = ANY ((ARRAY['M'::character varying, 'F'::character varying, 'Other'::character varying])::text[])))
);


ALTER TABLE public.passenger OWNER TO postgres;

--
-- Name: findseniorcitizen; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.findseniorcitizen AS
 SELECT passenger.pass_id,
    passenger.name,
    passenger.age,
    passenger.gender,
    passenger.nationality,
    passenger.concsn_type,
    passenger.user_id,
    pass_tkt.pnr_no,
    pass_tkt.src_date,
    pass_tkt.booking_id,
    pass_tkt.train_no,
    pass_tkt.coach_no,
    pass_tkt.seat_no,
    pass_tkt.food_order_id,
    pass_tkt.src,
    pass_tkt.dest,
    pass_tkt."isConfirmed"
   FROM (public.passenger
     JOIN public.pass_tkt USING (pass_id))
  WHERE (passenger.age > 60);


ALTER TABLE public.findseniorcitizen OWNER TO postgres;

--
-- Name: food; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food (
    food_order_id integer NOT NULL,
    item character varying(50) NOT NULL,
    booking_id integer,
    price numeric,
    del_time timestamp without time zone
);


ALTER TABLE public.food OWNER TO postgres;

--
-- Name: food_ordered; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_ordered (
    food_order_id integer NOT NULL,
    item character varying(50) NOT NULL,
    pass_id integer NOT NULL,
    pnr_no numeric NOT NULL
);


ALTER TABLE public.food_ordered OWNER TO postgres;

--
-- Name: new_user; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.new_user (
    user_id integer NOT NULL,
    name character varying(30),
    email character varying(50),
    "phNo" numeric,
    aadhar numeric,
    address character varying(50),
    dob timestamp without time zone,
    password character varying(20)
);


ALTER TABLE public.new_user OWNER TO postgres;

--
-- Name: parcel_tkt; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.parcel_tkt (
    parcel_no integer NOT NULL,
    booking_id integer,
    train_no integer,
    src character varying(5),
    dest character varying(5),
    weight integer,
    "isConfirmed" character varying(1)
);


ALTER TABLE public.parcel_tkt OWNER TO postgres;

--
-- Name: reservation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reservation (
    src_date timestamp without time zone NOT NULL,
    train_no integer NOT NULL,
    coach_no character varying(5) NOT NULL,
    coach_type character varying(5),
    seat_no integer NOT NULL,
    station character varying(4) NOT NULL,
    is_booked character varying(1) NOT NULL,
    seat_type character varying(5),
    CONSTRAINT reservation_is_booked_check CHECK (((is_booked)::text = ANY ((ARRAY['Y'::character varying, 'N'::character varying])::text[]))),
    CONSTRAINT reservation_seat_type_check CHECK (((seat_type)::text = ANY ((ARRAY['W'::character varying, 'M'::character varying, 'A'::character varying, 'SU'::character varying, 'SL'::character varying, 'UB'::character varying, 'LB'::character varying, 'MB'::character varying])::text[])))
);


ALTER TABLE public.reservation OWNER TO postgres;

--
-- Name: schedule; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.schedule (
    train_no integer NOT NULL,
    stn_id character varying(4) NOT NULL,
    days_of_wk integer NOT NULL,
    arr_time time without time zone,
    dep_time time without time zone,
    "Dayofjny" integer NOT NULL
);


ALTER TABLE public.schedule OWNER TO postgres;

--
-- Name: seat_status; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.seat_status (
    train_no integer NOT NULL,
    coach_no character varying(5) NOT NULL,
    seat_no integer NOT NULL,
    occupancy_status character varying(10) NOT NULL,
    current_pass_id integer,
    current_pnr_no integer,
    CONSTRAINT seat_status_occupancy_status_check CHECK (((occupancy_status)::text = ANY ((ARRAY['AVAILABLE'::character varying, 'BOOKED'::character varying, 'CONFIRMED'::character varying])::text[])))
);


ALTER TABLE public.seat_status OWNER TO postgres;

--
-- Name: station; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.station (
    stn_id character varying(4) NOT NULL,
    station_name character varying(20),
    address character varying(60)
);


ALTER TABLE public.station OWNER TO postgres;

--
-- Name: stns; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stns (
    stn_id character varying(4)
);


ALTER TABLE public.stns OWNER TO postgres;

--
-- Name: temptable; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.temptable (
    passr_id integer
);


ALTER TABLE public.temptable OWNER TO postgres;

--
-- Name: train; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.train (
    train_no integer NOT NULL,
    train_name character varying(20) NOT NULL,
    src character varying(4) NOT NULL,
    dest character varying(4) NOT NULL
);


ALTER TABLE public.train OWNER TO postgres;

--
-- Name: train_reservations; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.train_reservations AS
 SELECT r.train_no,
    count(*) AS reservations
   FROM (public.reservation r
     JOIN public.train t ON (((r.train_no = t.train_no) AND ((r.is_booked)::text = 'Y'::text))))
  GROUP BY r.train_no;


ALTER TABLE public.train_reservations OWNER TO postgres;

--
-- Name: tt_view; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.tt_view AS
 SELECT pass_tkt.pnr_no,
    passenger.name,
    passenger.age,
    passenger.gender,
    pass_tkt.coach_no,
    pass_tkt.seat_no,
    pass_tkt.src,
    pass_tkt.dest
   FROM (public.pass_tkt
     JOIN public.passenger USING (pass_id))
  WHERE ((pass_tkt.train_no = 16606) AND ((pass_tkt."isConfirmed")::text = 'CNF'::text))
  ORDER BY pass_tkt.coach_no, pass_tkt.seat_no;


ALTER TABLE public.tt_view OWNER TO postgres;

--
-- Data for Name: booking; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.booking (booking_id, fare, txn_id, user_id, booking_date) FROM stdin;
73772234	155	551327	5533	2023-05-06 12:59:52.098669
73772234	-50	1102655	5533	2023-05-06 13:00:09.164512
73772236	185	816249	5678	2023-05-06 13:11:13.340884
73772236	-25	1632499	5678	2023-05-06 13:11:27.102189
73772238	125	652954	5678	2023-05-06 13:13:30.160845
73772238	-75	1305909	5678	2023-05-06 13:13:46.136007
73772240	125	731441	5678	2023-05-06 13:23:38.259449
73772240	-75	1462883	5678	2023-05-06 13:24:15.920758
73772242	515	839895	5533	2023-05-06 14:13:20.318063
73772242	-200	1679791	5533	2023-05-06 14:15:22.129757
73772242	-200	3359583	5533	2023-05-06 14:16:18.145363
73772245	155	432394	5533	2023-05-12 18:32:20.848426
73772246	215	589661	5533	2023-05-12 18:49:22.40677
\.


--
-- Data for Name: food; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food (food_order_id, item, booking_id, price, del_time) FROM stdin;
\.


--
-- Data for Name: food_ordered; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_ordered (food_order_id, item, pass_id, pnr_no) FROM stdin;
\.


--
-- Data for Name: new_user; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.new_user (user_id, name, email, "phNo", aadhar, address, dob, password) FROM stdin;
1234	NAM	ww@ww.com	9699	9696969	addr qwwr  aw, aew, r	2023-05-02 00:00:00	pass123
5533	NAM4	s24ww@w4w.com	9699	69696969	addr qwwr  aw, a2ew, r	2003-05-02 00:00:00	0000
112001051	vmsreeram	a@gmail.com	977	11223344	a h nj wajnkjfkn jwan ,sd,g,sd	2002-09-19 00:00:00	aaaa
1122	somename	12@ana.add	112222333	1222334	24, 23,r qwra,az	2002-09-19 00:00:00	1122pass
998877	abcd	efgh@wmmm.wsw	444444	222222	44m.we.,3r32,rq3rw,	2020-09-19 00:00:00	9999
12431	rajdhani	rajdhani@gmail.com	12431	12431	12431	2012-04-12 00:00:00	raj
5678	aaaa	aaaa	9999	3333	ne4jd	2020-01-30 00:00:00	5678
\.


--
-- Data for Name: parcel_tkt; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.parcel_tkt (parcel_no, booking_id, train_no, src, dest, weight, "isConfirmed") FROM stdin;
\.


--
-- Data for Name: pass_tkt; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pass_tkt (pnr_no, src_date, pass_id, booking_id, train_no, coach_no, seat_no, food_order_id, src, dest, "isConfirmed") FROM stdin;
56734512	2023-05-06 00:00:00	10	73772234	16606	C2	4	\N	ALLP	ERS	CAN
56734512	2023-05-06 00:00:00	11	73772234	16606	C2	3	\N	ALLP	ERS	CAN
56734514	2023-05-06 00:00:00	5	73772236	16606	C1	1	\N	TVC	CLT	CAN
56734515	2023-05-06 00:00:00	5	73772238	16606	C1	1	\N	ERS	CLT	CAN
56734516	2023-05-06 00:00:00	5	73772240	16606	C1	1	\N	ERS	CLT	CAN
56734517	2023-05-06 00:00:00	6	73772242	16606	C1	1	\N	ALLP	CLT	CAN
56734517	2023-05-06 00:00:00	8	73772242	16606	C1	3	\N	ALLP	CLT	CAN
56734517	2023-05-06 00:00:00	7	73772242	16606	C1	2	\N	ALLP	CLT	CAN
56734517	2023-05-06 00:00:00	9	73772242	16606	C1	4	\N	ALLP	CLT	CAN
56734521	2023-05-06 00:00:00	8	73772245	16606	C1	1	\N	ALLP	ERS	CNF
56734521	2023-05-06 00:00:00	9	73772245	16606	C1	2	\N	ALLP	ERS	CNF
56734523	2023-05-06 00:00:00	7	73772246	16606	C2	4	\N	TVC	ERS	CNF
56734523	2023-05-06 00:00:00	9	73772246	16606	C2	3	\N	TVC	ERS	CNF
\.


--
-- Data for Name: passenger; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.passenger (pass_id, name, age, gender, nationality, concsn_type, user_id) FROM stdin;
5	sai	20	F	canada	student	5678
6	Sai	20	F	Indian	other	5533
7	Bai	23	M	Indian	armed_forces	5533
8	Tai	25	F	Japan	other	5533
9	Kai	63	M	Greek	senior_ctzn	5533
10	qai	33	M	USA	other	5533
\.


--
-- Data for Name: reservation; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reservation (src_date, train_no, coach_no, coach_type, seat_no, station, is_booked, seat_type) FROM stdin;
2023-05-23 00:00:00	12076	C1	CC	1	QLN	N	W
2023-05-23 00:00:00	12076	C1	CC	1	ALLP	N	W
2023-05-06 00:00:00	16606	C1	CC	3	SRR	N	A
2023-05-23 00:00:00	12076	C1	CC	1	TVC	N	W
2023-05-23 00:00:00	12076	C1	CC	1	CLT	N	W
2023-05-23 00:00:00	12076	C1	CC	2	TVC	N	M
2023-05-06 00:00:00	16606	C1	CC	4	SRR	N	W
2023-05-23 00:00:00	12076	C1	CC	3	QLN	N	A
2023-05-23 00:00:00	12076	C1	CC	3	ALLP	N	A
2023-05-23 00:00:00	12076	C1	CC	3	ERS	N	A
2023-05-23 00:00:00	12076	C1	CC	3	SRR	N	A
2023-05-23 00:00:00	12076	C1	CC	4	QLN	N	M
2023-05-23 00:00:00	12076	C1	CC	4	ALLP	N	M
2023-05-23 00:00:00	12076	C1	CC	4	ERS	N	M
2023-05-23 00:00:00	12076	C1	CC	4	SRR	N	M
2023-05-06 00:00:00	12431	H1	1AC	3	TVC	N	A
2023-05-06 00:00:00	12431	H1	1AC	3	QLN	N	A
2023-05-06 00:00:00	12431	H1	1AC	3	ALLP	N	A
2023-05-06 00:00:00	12431	H1	1AC	3	ERS	N	A
2023-05-06 00:00:00	12431	H1	1AC	3	SRR	N	A
2023-05-06 00:00:00	16606	C2	3AC	4	TVC	Y	W
2023-05-06 00:00:00	12431	B2	3AC	1	CLT	N	W
2023-05-06 00:00:00	12431	B2	3AC	2	CLT	N	M
2023-05-06 00:00:00	16606	C2	3AC	4	ALLP	Y	W
2023-05-06 00:00:00	16606	C1	CC	1	ERS	N	W
2023-05-06 00:00:00	16606	C1	CC	2	ERS	N	M
2023-05-23 00:00:00	12076	C1	CC	2	CLT	N	M
2023-05-23 00:00:00	12076	C1	CC	3	TVC	N	A
2023-05-23 00:00:00	12076	C1	CC	3	CLT	N	A
2023-05-23 00:00:00	12076	C1	CC	4	TVC	N	M
2023-05-23 00:00:00	12076	C1	CC	4	CLT	N	M
2023-05-23 00:00:00	12076	C2	3AC	1	TVC	N	W
2023-05-23 00:00:00	12076	C2	3AC	1	ERS	N	W
2023-05-23 00:00:00	12076	C2	3AC	1	SRR	N	W
2023-05-23 00:00:00	12076	C2	3AC	1	CLT	N	W
2023-05-23 00:00:00	12076	C2	3AC	2	TVC	N	M
2023-05-23 00:00:00	12076	C2	3AC	2	ERS	N	M
2023-05-23 00:00:00	12076	C2	3AC	2	SRR	N	M
2023-05-23 00:00:00	12076	C2	3AC	2	CLT	N	M
2023-05-23 00:00:00	12076	C2	3AC	3	TVC	N	A
2023-05-23 00:00:00	12076	C2	3AC	3	ERS	N	A
2023-05-23 00:00:00	12076	C2	3AC	3	SRR	N	A
2023-05-23 00:00:00	12076	C2	3AC	3	CLT	N	A
2023-05-23 00:00:00	12076	C2	3AC	4	TVC	N	W
2023-05-23 00:00:00	12076	C2	3AC	4	QLN	N	W
2023-05-23 00:00:00	12076	C2	3AC	4	ALLP	N	W
2023-05-23 00:00:00	12076	C2	3AC	4	ERS	N	W
2023-05-23 00:00:00	12076	C2	3AC	4	SRR	N	W
2023-05-23 00:00:00	12076	C2	3AC	4	CLT	N	W
2023-05-06 00:00:00	16606	C1	CC	1	QLN	N	W
2023-05-06 00:00:00	16606	C1	CC	1	CLT	N	W
2023-05-06 00:00:00	16606	C1	CC	1	CAN	N	W
2023-05-06 00:00:00	16606	C1	CC	1	MAQ	N	W
2023-05-06 00:00:00	16606	C1	CC	2	QLN	N	M
2023-05-06 00:00:00	16606	C1	CC	2	CLT	N	M
2023-05-06 00:00:00	16606	C1	CC	2	CAN	N	M
2023-05-06 00:00:00	16606	C1	CC	2	MAQ	N	M
2023-05-06 00:00:00	16606	C1	CC	3	QLN	N	A
2023-05-06 00:00:00	16606	C1	CC	3	CLT	N	A
2023-05-06 00:00:00	16606	C1	CC	3	CAN	N	A
2023-05-06 00:00:00	16606	C1	CC	3	MAQ	N	A
2023-05-06 00:00:00	16606	C1	CC	4	QLN	N	W
2023-05-06 00:00:00	16606	C1	CC	4	CLT	N	W
2023-05-06 00:00:00	16606	C1	CC	4	CAN	N	W
2023-05-06 00:00:00	16606	C1	CC	4	MAQ	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	TVC	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	QLN	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	ALLP	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	CLT	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	CAN	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	MAQ	N	W
2023-05-06 00:00:00	16606	C2	3AC	2	TVC	N	M
2023-05-06 00:00:00	16606	C2	3AC	2	QLN	N	M
2023-05-06 00:00:00	16606	C2	3AC	2	ALLP	N	M
2023-05-06 00:00:00	16606	C2	3AC	2	CLT	N	M
2023-05-06 00:00:00	16606	C2	3AC	2	CAN	N	M
2023-05-06 00:00:00	16606	C2	3AC	2	MAQ	N	M
2023-05-06 00:00:00	16606	C2	3AC	3	QLN	N	A
2023-05-06 00:00:00	16606	C2	3AC	3	CLT	N	A
2023-05-06 00:00:00	16606	C2	3AC	3	CAN	N	A
2023-05-06 00:00:00	16606	C2	3AC	3	MAQ	N	A
2023-05-06 00:00:00	16606	C2	3AC	4	QLN	N	W
2023-05-06 00:00:00	16606	C2	3AC	4	CLT	N	W
2023-05-06 00:00:00	16606	C2	3AC	4	CAN	N	W
2023-05-06 00:00:00	16606	C2	3AC	4	MAQ	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	NZM	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	CLT	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	SRR	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	ERS	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	ALLP	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	QLN	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	TVC	N	W
2023-05-06 00:00:00	12432	H1	1AC	2	NZM	N	W
2023-05-06 00:00:00	12432	H1	1AC	2	CLT	N	M
2023-05-06 00:00:00	12432	H1	1AC	2	SRR	N	M
2023-05-06 00:00:00	12432	H1	1AC	2	ERS	N	M
2023-05-06 00:00:00	12432	H1	1AC	2	ALLP	N	M
2023-05-06 00:00:00	12432	H1	1AC	2	QLN	N	M
2023-05-06 00:00:00	12432	H1	1AC	2	TVC	N	M
2023-05-06 00:00:00	12432	H1	1AC	3	NZM	N	W
2023-05-06 00:00:00	12432	H1	1AC	3	CLT	N	A
2023-05-06 00:00:00	12432	H1	1AC	3	SRR	N	A
2023-05-06 00:00:00	12432	H1	1AC	3	ERS	N	A
2023-05-06 00:00:00	12432	H1	1AC	3	ALLP	N	A
2023-05-06 00:00:00	12432	H1	1AC	3	QLN	N	A
2023-05-06 00:00:00	12432	H1	1AC	3	TVC	N	A
2023-05-23 00:00:00	12076	C1	CC	1	ERS	N	W
2023-05-06 00:00:00	16606	C1	CC	1	SRR	N	W
2023-05-06 00:00:00	16606	C1	CC	3	ALLP	N	A
2023-05-23 00:00:00	12076	C1	CC	1	SRR	N	W
2023-05-23 00:00:00	12076	C2	3AC	1	QLN	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	ERS	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	SRR	N	W
2023-05-06 00:00:00	16606	C2	3AC	3	ERS	N	A
2023-05-23 00:00:00	12076	C2	3AC	2	ALLP	N	M
2023-05-23 00:00:00	12076	C2	3AC	2	QLN	N	M
2023-05-06 00:00:00	16606	C1	CC	3	ERS	N	A
2023-05-06 00:00:00	16606	C1	CC	2	SRR	N	M
2023-05-23 00:00:00	12076	C2	3AC	3	ALLP	N	A
2023-05-06 00:00:00	16606	C2	3AC	3	SRR	N	A
2023-05-23 00:00:00	12076	C2	3AC	1	ALLP	N	W
2023-05-23 00:00:00	12076	C1	CC	2	QLN	N	M
2023-05-06 00:00:00	16606	C1	CC	1	ALLP	Y	W
2023-05-06 00:00:00	16606	C1	CC	2	ALLP	Y	M
2023-05-23 00:00:00	12076	C1	CC	2	ALLP	N	M
2023-05-23 00:00:00	12076	C1	CC	2	ERS	N	M
2023-05-23 00:00:00	12076	C1	CC	2	SRR	N	M
2023-05-06 00:00:00	16606	C2	3AC	3	TVC	Y	A
2023-05-06 00:00:00	16606	C1	CC	4	ALLP	N	W
2023-05-23 00:00:00	12076	C2	3AC	3	QLN	N	A
2023-05-06 00:00:00	16606	C1	CC	4	ERS	N	W
2023-05-06 00:00:00	16606	C2	3AC	3	ALLP	Y	A
2023-05-06 00:00:00	12431	B2	3AC	1	SRR	N	W
2023-05-06 00:00:00	16606	C2	3AC	2	ERS	N	M
2023-05-06 00:00:00	16606	C2	3AC	2	SRR	N	M
2023-05-06 00:00:00	12432	H1	1AC	4	NZM	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	CLT	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	SRR	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	ERS	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	ALLP	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	QLN	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	TVC	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	NZM	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	CLT	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	SRR	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	ERS	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	ALLP	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	QLN	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	TVC	N	W
2023-05-06 00:00:00	12432	A1	2AC	2	NZM	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	CLT	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	SRR	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	ERS	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	ALLP	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	QLN	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	TVC	N	M
2023-05-06 00:00:00	12432	A1	2AC	3	NZM	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	CLT	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	SRR	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	ERS	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	ALLP	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	QLN	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	TVC	N	A
2023-05-06 00:00:00	12432	A1	2AC	4	NZM	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	CLT	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	SRR	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	ERS	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	ALLP	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	QLN	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	TVC	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	NZM	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	CLT	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	SRR	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	ERS	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	ALLP	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	QLN	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	TVC	N	W
2023-05-06 00:00:00	12432	A2	2AC	2	NZM	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	CLT	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	SRR	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	ERS	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	ALLP	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	QLN	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	TVC	N	M
2023-05-06 00:00:00	12432	A2	2AC	3	NZM	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	CLT	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	SRR	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	ERS	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	ALLP	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	QLN	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	TVC	N	A
2023-05-06 00:00:00	12432	A2	2AC	4	NZM	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	CLT	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	SRR	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	ERS	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	ALLP	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	QLN	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	TVC	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	NZM	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	CLT	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	SRR	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	ERS	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	ALLP	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	QLN	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	TVC	N	W
2023-05-06 00:00:00	12432	B1	3AC	2	NZM	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	CLT	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	SRR	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	ERS	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	ALLP	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	QLN	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	TVC	N	M
2023-05-06 00:00:00	12432	B1	3AC	3	NZM	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	CLT	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	SRR	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	ERS	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	ALLP	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	QLN	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	TVC	N	A
2023-05-06 00:00:00	12432	B1	3AC	4	NZM	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	CLT	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	SRR	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	ERS	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	ALLP	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	QLN	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	TVC	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	NZM	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	CLT	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	SRR	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	ERS	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	ALLP	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	QLN	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	TVC	N	W
2023-05-06 00:00:00	12432	B2	3AC	2	NZM	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	CLT	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	SRR	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	ERS	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	ALLP	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	QLN	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	TVC	N	M
2023-05-06 00:00:00	12432	B2	3AC	3	NZM	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	CLT	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	SRR	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	ERS	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	ALLP	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	QLN	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	TVC	N	A
2023-05-06 00:00:00	12432	B2	3AC	4	NZM	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	CLT	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	SRR	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	ERS	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	ALLP	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	QLN	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	TVC	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	TVC	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	QLN	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	ALLP	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	ERS	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	SRR	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	CLT	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	NZM	N	W
2023-05-06 00:00:00	12431	H1	1AC	2	TVC	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	QLN	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	ALLP	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	ERS	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	SRR	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	CLT	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	NZM	N	M
2023-05-06 00:00:00	12431	H1	1AC	3	CLT	N	A
2023-05-06 00:00:00	12431	H1	1AC	3	NZM	N	A
2023-05-06 00:00:00	12431	H1	1AC	4	TVC	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	QLN	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	ALLP	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	ERS	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	SRR	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	CLT	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	NZM	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	TVC	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	QLN	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	ALLP	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	ERS	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	SRR	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	CLT	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	NZM	N	W
2023-05-06 00:00:00	12431	A1	2AC	2	TVC	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	QLN	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	ALLP	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	ERS	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	SRR	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	CLT	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	NZM	N	M
2023-05-06 00:00:00	12431	A1	2AC	3	TVC	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	QLN	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	ALLP	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	ERS	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	SRR	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	CLT	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	NZM	N	A
2023-05-06 00:00:00	12431	A1	2AC	4	TVC	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	QLN	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	ALLP	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	ERS	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	SRR	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	CLT	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	NZM	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	TVC	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	QLN	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	ALLP	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	ERS	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	SRR	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	CLT	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	NZM	N	W
2023-05-06 00:00:00	12431	A2	2AC	2	TVC	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	QLN	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	ALLP	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	ERS	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	SRR	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	CLT	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	NZM	N	M
2023-05-06 00:00:00	12431	A2	2AC	3	TVC	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	QLN	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	ALLP	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	ERS	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	SRR	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	CLT	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	NZM	N	A
2023-05-06 00:00:00	12431	A2	2AC	4	TVC	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	QLN	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	ALLP	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	ERS	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	SRR	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	CLT	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	NZM	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	TVC	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	QLN	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	ALLP	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	ERS	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	SRR	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	CLT	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	NZM	N	W
2023-05-06 00:00:00	12431	B1	3AC	2	TVC	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	QLN	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	ALLP	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	ERS	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	SRR	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	CLT	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	NZM	N	M
2023-05-06 00:00:00	12431	B1	3AC	3	TVC	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	QLN	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	ALLP	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	ERS	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	SRR	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	CLT	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	NZM	N	A
2023-05-06 00:00:00	12431	B1	3AC	4	TVC	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	QLN	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	ALLP	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	ERS	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	SRR	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	CLT	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	NZM	N	W
2023-05-06 00:00:00	12431	B2	3AC	1	TVC	N	W
2023-05-06 00:00:00	12431	B2	3AC	1	NZM	N	W
2023-05-06 00:00:00	12431	B2	3AC	2	TVC	N	M
2023-05-06 00:00:00	12431	B2	3AC	2	NZM	N	M
2023-05-06 00:00:00	12431	B2	3AC	3	TVC	N	A
2023-05-06 00:00:00	12431	B2	3AC	3	QLN	N	A
2023-05-06 00:00:00	12431	B2	3AC	3	ALLP	N	A
2023-05-06 00:00:00	12431	B2	3AC	3	CLT	N	A
2023-05-06 00:00:00	12431	B2	3AC	3	NZM	N	A
2023-05-06 00:00:00	12431	B2	3AC	4	TVC	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	QLN	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	ALLP	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	ERS	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	SRR	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	CLT	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	NZM	N	W
2023-05-06 00:00:00	16606	C1	CC	4	TVC	N	W
2023-05-06 00:00:00	12431	B2	3AC	1	QLN	N	W
2023-05-06 00:00:00	12431	B2	3AC	1	ALLP	N	W
2023-05-06 00:00:00	12431	B2	3AC	2	QLN	N	M
2023-05-06 00:00:00	12431	B2	3AC	2	ALLP	N	M
2023-05-06 00:00:00	12431	B2	3AC	2	ERS	N	M
2023-05-06 00:00:00	12431	B2	3AC	2	SRR	N	M
2023-05-06 00:00:00	16606	C1	CC	1	TVC	N	W
2023-05-06 00:00:00	16606	C1	CC	2	TVC	N	M
2023-05-06 00:00:00	16606	C1	CC	3	TVC	N	A
2023-05-06 00:00:00	16606	C2	3AC	4	ERS	N	W
2023-05-06 00:00:00	16606	C2	3AC	4	SRR	N	W
2023-05-06 00:00:00	12431	B2	3AC	3	ERS	N	A
2023-05-06 00:00:00	12431	B2	3AC	3	SRR	N	A
2023-05-06 00:00:00	12431	B2	3AC	1	ERS	N	W
\.


--
-- Data for Name: schedule; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.schedule (train_no, stn_id, days_of_wk, arr_time, dep_time, "Dayofjny") FROM stdin;
16606	NCJ	127	\N	02:00:00	1
16606	TVC	127	03:30:00	03:35:00	1
16606	ALLP	127	06:15:00	06:18:00	1
16606	ERS	127	07:45:00	07:50:00	1
16606	SRR	127	10:40:00	10:45:00	1
16606	CLT	127	12:32:00	12:35:00	1
16606	CAN	127	14:12:00	14:15:00	1
16606	MAQ	127	18:00:00	\N	1
12431	TVC	26	\N	19:15:00	1
12431	QLN	26	20:11:00	20:13:00	1
12431	ALLP	26	21:33:00	21:35:00	1
12431	ERS	26	22:30:00	22:35:00	1
12431	SRR	52	00:45:00	00:50:00	2
12431	CLT	52	01:57:00	02:00:00	2
12431	NZM	104	12:30:00	\N	3
12076	TVC	127	\N	05:55:00	1
12076	QLN	127	06:55:00	06:57:00	1
12076	ALLP	127	08:13:00	08:15:00	1
12076	ERS	127	09:12:00	09:17:00	1
12076	SRR	127	11:25:00	11:28:00	1
12076	CLT	127	12:55:00	\N	1
12082	TVC	93	\N	14:45:00	1
12082	QLN	93	15:38:00	15:40:00	1
12082	KTYM	93	17:18:00	17:20:00	1
12082	ERS	93	18:30:00	18:35:00	1
12082	TCR	93	19:48:00	19:50:00	1
12082	SRR	93	20:52:00	20:55:00	1
12082	CLT	93	22:17:00	22:20:00	1
12082	CAN	110	00:20:00	\N	2
22208	TVC	17	\N	19:15:00	1
22208	QLN	17	20:11:00	20:13:00	1
22208	ALLP	17	21:33:00	21:35:00	1
22208	ERN	17	22:30:00	22:35:00	1
22208	TCR	17	23:48:00	23:50:00	1
22208	CBE	72	02:42:00	02:45:00	2
22208	SA	72	05:19:00	05:12:00	2
22208	MAS	72	10:15:00	\N	2
16605	MAQ	127	\N	07:20:00	1
16605	CAN	127	09:32:00	09:35:00	1
16605	CLT	127	11:07:00	11:10:00	1
16605	SRR	127	13:25:00	13:30:00	1
16605	ERS	127	16:15:00	16:20:00	1
16605	ALLP	127	17:48:00	17:50:00	1
16605	TVC	127	20:50:00	20:55:00	1
16605	NCJ	127	23:20:00	\N	1
12432	NZM	49	\N	06:16:00	1
12432	CLT	88	15:17:00	15:20:00	2
12432	SRR	88	16:55:00	17:00:00	2
12432	ERS	88	19:15:00	19:20:00	2
12432	ALLP	88	20:32:00	20:35:00	2
12432	QLN	88	21:53:00	21:55:00	2
12432	TVC	88	23:35:00	\N	2
\.


--
-- Data for Name: seat_status; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.seat_status (train_no, coach_no, seat_no, occupancy_status, current_pass_id, current_pnr_no) FROM stdin;
\.


--
-- Data for Name: station; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.station (stn_id, station_name, address) FROM stdin;
ERS	Ernakulam Jn	-
TVC	Trivandrum Central	-
ALLP	Alappuzha	-
CLT	Kozhikkode	-
SRR	Shoranur Jn	-
NZM	Hazrat Nizamuddin	-
QLN	Kollam Jn	-
CAN	Kannur	-
\.


--
-- Data for Name: stns; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stns (stn_id) FROM stdin;
\.


--
-- Data for Name: temptable; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.temptable (passr_id) FROM stdin;
1234
9876
\.


--
-- Data for Name: train; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.train (train_no, train_name, src, dest) FROM stdin;
16606	ERNAD EXPRESS	NCJ	MAQ
12431	RAJDHANI EXP	TVC	NZM
12076	CLT JANSHATABDI	TVC	CLT
12082	CAN JANSHATABDI	TVC	CAN
22208	MAS SF AC EXP	TVC	MAS
16605	ERNAD EXPRESS	NCJ	MAQ
12432	TVC RAJDHANI	NZM	TVC
\.


--
-- Name: booking booking_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.booking
    ADD CONSTRAINT booking_pkey PRIMARY KEY (booking_id, txn_id);


--
-- Name: food_ordered food_ordered_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_ordered
    ADD CONSTRAINT food_ordered_pkey PRIMARY KEY (food_order_id, item, pass_id, pnr_no);


--
-- Name: food food_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food
    ADD CONSTRAINT food_pkey PRIMARY KEY (food_order_id, item);


--
-- Name: new_user new_user_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.new_user
    ADD CONSTRAINT new_user_pkey PRIMARY KEY (user_id);


--
-- Name: parcel_tkt parcel_tkt_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.parcel_tkt
    ADD CONSTRAINT parcel_tkt_pkey PRIMARY KEY (parcel_no);


--
-- Name: pass_tkt pass_tkt_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pass_tkt
    ADD CONSTRAINT pass_tkt_pkey PRIMARY KEY (pnr_no, pass_id);


--
-- Name: passenger passenger_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.passenger
    ADD CONSTRAINT passenger_pkey PRIMARY KEY (pass_id);


--
-- Name: reservation reservation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservation
    ADD CONSTRAINT reservation_pkey PRIMARY KEY (src_date, train_no, coach_no, seat_no, station);


--
-- Name: schedule schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule
    ADD CONSTRAINT schedule_pkey PRIMARY KEY (train_no, stn_id, days_of_wk);


--
-- Name: seat_status seat_status_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.seat_status
    ADD CONSTRAINT seat_status_pkey PRIMARY KEY (train_no, coach_no, seat_no);


--
-- Name: station station_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.station
    ADD CONSTRAINT station_pkey PRIMARY KEY (stn_id);


--
-- Name: train train_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.train
    ADD CONSTRAINT train_pkey PRIMARY KEY (train_no);


--
-- Name: btree_dayofjny_schedule; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX btree_dayofjny_schedule ON public.schedule USING btree ("Dayofjny");


--
-- Name: btree_src_date_pass_tkt; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX btree_src_date_pass_tkt ON public.pass_tkt USING btree (src_date);


--
-- Name: btree_src_date_reservation; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX btree_src_date_reservation ON public.reservation USING btree (src_date);


--
-- Name: hash_train_no_parcel_tkt; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX hash_train_no_parcel_tkt ON public.parcel_tkt USING hash (train_no);


--
-- Name: hash_train_no_pass_tkt; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX hash_train_no_pass_tkt ON public.pass_tkt USING hash (train_no);


--
-- Name: hash_train_no_reservation; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX hash_train_no_reservation ON public.reservation USING hash (train_no);


--
-- Name: hash_train_no_schedule; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX hash_train_no_schedule ON public.schedule USING hash (train_no);


--
-- Name: hash_train_no_train; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX hash_train_no_train ON public.train USING hash (train_no);


--
-- Name: schedule add_reservation_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER add_reservation_trigger AFTER INSERT ON public.schedule FOR EACH ROW EXECUTE FUNCTION public.add_reservation_trigger();


--
-- Name: new_user delete_passenger_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER delete_passenger_trigger AFTER DELETE ON public.new_user FOR EACH ROW EXECUTE FUNCTION public.delete_passenger_trigger();


--
-- Name: reservation update_pass_tkt_status_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_pass_tkt_status_trigger AFTER UPDATE ON public.reservation FOR EACH ROW EXECUTE FUNCTION public.update_pass_tkt_status_trigger();


--
-- Name: pass_tkt pass_tkt_train_no_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pass_tkt
    ADD CONSTRAINT pass_tkt_train_no_fkey FOREIGN KEY (train_no) REFERENCES public.train(train_no);


--
-- Name: reservation reservation_train_no_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservation
    ADD CONSTRAINT reservation_train_no_fkey FOREIGN KEY (train_no) REFERENCES public.train(train_no);


--
-- Name: seat_status seat_status_train_no_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.seat_status
    ADD CONSTRAINT seat_status_train_no_fkey FOREIGN KEY (train_no) REFERENCES public.train(train_no);


--
-- Name: FUNCTION add_reservation_trigger(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.add_reservation_trigger() TO railway_manager;
GRANT ALL ON FUNCTION public.add_reservation_trigger() TO reservation_clerk;


--
-- Name: PROCEDURE cancel_seat(IN pnr_no_ integer, IN usr_id integer, IN pass_ids text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.cancel_seat(IN pnr_no_ integer, IN usr_id integer, IN pass_ids text) TO railway_manager;
GRANT ALL ON PROCEDURE public.cancel_seat(IN pnr_no_ integer, IN usr_id integer, IN pass_ids text) TO reservation_clerk;


--
-- Name: PROCEDURE cancel_ticket(IN p_pnr_no integer, IN p_pass_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.cancel_ticket(IN p_pnr_no integer, IN p_pass_id integer) TO railway_manager;
GRANT ALL ON PROCEDURE public.cancel_ticket(IN p_pnr_no integer, IN p_pass_id integer) TO reservation_clerk;


--
-- Name: FUNCTION delete_passenger_trigger(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.delete_passenger_trigger() TO railway_manager;
GRANT ALL ON FUNCTION public.delete_passenger_trigger() TO reservation_clerk;


--
-- Name: FUNCTION num_available(tno integer, src character varying, dst character varying, doj timestamp without time zone, c_typ character varying); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.num_available(tno integer, src character varying, dst character varying, doj timestamp without time zone, c_typ character varying) TO railway_manager;
GRANT ALL ON FUNCTION public.num_available(tno integer, src character varying, dst character varying, doj timestamp without time zone, c_typ character varying) TO reservation_clerk;


--
-- Name: PROCEDURE reserve_seat(IN tno integer, IN src character varying, IN dst character varying, IN doj timestamp without time zone, IN c_typ character varying, IN usr_id integer, IN trxn_id integer, IN pass_ids text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.reserve_seat(IN tno integer, IN src character varying, IN dst character varying, IN doj timestamp without time zone, IN c_typ character varying, IN usr_id integer, IN trxn_id integer, IN pass_ids text) TO railway_manager;
GRANT ALL ON PROCEDURE public.reserve_seat(IN tno integer, IN src character varying, IN dst character varying, IN doj timestamp without time zone, IN c_typ character varying, IN usr_id integer, IN trxn_id integer, IN pass_ids text) TO reservation_clerk;


--
-- Name: FUNCTION station_between(p_train_no integer, p_start_stn character varying, p_end_stn character varying); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.station_between(p_train_no integer, p_start_stn character varying, p_end_stn character varying) TO railway_manager;
GRANT ALL ON FUNCTION public.station_between(p_train_no integer, p_start_stn character varying, p_end_stn character varying) TO reservation_clerk;


--
-- Name: FUNCTION trainsbtwstns(src_id character varying, dst_id character varying, day integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trainsbtwstns(src_id character varying, dst_id character varying, day integer) TO railway_manager;
GRANT ALL ON FUNCTION public.trainsbtwstns(src_id character varying, dst_id character varying, day integer) TO reservation_clerk;


--
-- Name: FUNCTION update_pass_tkt_status_trigger(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_pass_tkt_status_trigger() TO railway_manager;
GRANT ALL ON FUNCTION public.update_pass_tkt_status_trigger() TO reservation_clerk;


--
-- Name: TABLE booking; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.booking TO railway_manager;


--
-- Name: TABLE pass_tkt; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.pass_tkt TO railway_manager;


--
-- Name: TABLE passenger; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.passenger TO railway_manager;


--
-- Name: TABLE findseniorcitizen; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.findseniorcitizen TO railway_manager;


--
-- Name: TABLE food; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.food TO railway_manager;


--
-- Name: TABLE food_ordered; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.food_ordered TO railway_manager;


--
-- Name: TABLE new_user; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.new_user TO railway_manager;


--
-- Name: TABLE parcel_tkt; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.parcel_tkt TO railway_manager;


--
-- Name: TABLE reservation; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.reservation TO railway_manager;


--
-- Name: TABLE schedule; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.schedule TO railway_manager;


--
-- Name: TABLE seat_status; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.seat_status TO railway_manager;


--
-- Name: TABLE station; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.station TO railway_manager;


--
-- Name: TABLE stns; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.stns TO railway_manager;


--
-- Name: TABLE temptable; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.temptable TO railway_manager;


--
-- Name: TABLE train; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.train TO railway_manager;


--
-- Name: TABLE train_reservations; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.train_reservations TO railway_manager;


--
-- Name: TABLE tt_view; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tt_view TO railway_manager;


--
-- PostgreSQL database dump complete
--

