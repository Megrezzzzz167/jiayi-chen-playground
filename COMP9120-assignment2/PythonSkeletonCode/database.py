#!/usr/bin/env python3
import psycopg2

#####################################################
##  Database Connection
#####################################################

'''
Connect to the database using the connection string
'''
def openConnection():
    # connection parameters - ENTER YOUR LOGIN AND PASSWORD HERE

    myHost = "your_host_name_here"
    userid = "your_user_id_here"
    passwd = "your_password_here"

    # Create a connection to the database
    conn = None
    try:
        # Parses the config file and connects using the connect string
        conn = psycopg2.connect(database=userid,
                                    user=userid,
                                    password=passwd,
                                    host=myHost)

    except psycopg2.Error as sqle:
        print("psycopg2.Error : " + str(sqle))

    # return the connection to use
    return conn

def _dict_rows(cursor):
    columns = [desc[0] for desc in cursor.description]
    rows = []
    for row in cursor.fetchall():
        rows.append(dict(zip(columns, row)))
    return rows

def _normalise_winner(value):
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in ('yes', 'y', 'true', 't', '1')

"""
    Checks the login credentials for an official user
"""
def checkLogin(login, password):
    conn = openConnection()
    if conn is None:
        return None

    cur = None
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT username, firstname, lastname
            FROM official
            WHERE lower(username) = lower(%s)
              AND password = %s
        """, (login, password))
        row = cur.fetchone()
        if row is None:
            return None
        return [row[0], row[1], row[2]]
    except psycopg2.Error as sqle:
        print("psycopg2.Error : " + str(sqle))
        return None
    finally:
        if cur is not None:
            cur.close()
        conn.close()

"""
    Retrieves a summary of each athlete's trials, including scheduled and completed trials, wins, equipment, sponsorship, and most recent trial date.
"""
def getAthleteTrialsSummary():
    conn = openConnection()
    if conn is None:
        return None

    cur = None
    try:
        cur = conn.cursor()
        cur.execute("""
            WITH participation_summary AS (
                SELECT
                    p.athlete_id,
                    COUNT(*) FILTER (WHERE p.status = 'scheduled') AS trials_scheduled,
                    COUNT(*) FILTER (WHERE p.status = 'completed') AS trials_completed,
                    COUNT(*) FILTER (WHERE p.is_winner) AS trials_wins,
                    MAX(t.trial_date) FILTER (WHERE p.status = 'completed') AS last_trial_date
                FROM participation p
                JOIN trials t ON t.trial_id = p.trial_id
                GROUP BY p.athlete_id
            ),
            equipment_summary AS (
                SELECT
                    aid AS athlete_id,
                    COUNT(*) AS equipment_count
                FROM equipment
                WHERE condition_status IN ('good', 'very good', 'excellent')
                GROUP BY aid
            ),
            sponsorship_summary AS (
                SELECT
                    athlete_id,
                    COALESCE(SUM(amount), 0) AS sponsorship
                FROM sponsorship_payment
                GROUP BY athlete_id
            )
            SELECT
                a.username AS athlete_username,
                a.firstname || ' ' || a.lastname || ', ' ||
                    COALESCE(a.nationality, 'N/A') || ', ' ||
                    CASE
                        WHEN pro.athlete_id IS NOT NULL THEN 'Professional'
                        WHEN am.athlete_id IS NOT NULL THEN 'Amateur'
                        ELSE 'N/A'
                    END AS athlete_info,
                COALESCE(ps.trials_scheduled, 0) AS trials_scheduled,
                COALESCE(ps.trials_completed, 0) AS trials_completed,
                COALESCE(ps.trials_wins, 0) AS trials_wins,
                COALESCE(es.equipment_count, 0) AS equipment_count,
                COALESCE(ss.sponsorship, 0) AS sponsorship,
                COALESCE(to_char(ps.last_trial_date, 'DD-MM-YYYY'), 'N/A') AS last_trial_date
            FROM athlete a
            LEFT JOIN amateur am ON am.athlete_id = a.athlete_id
            LEFT JOIN professional pro ON pro.athlete_id = a.athlete_id
            LEFT JOIN participation_summary ps ON ps.athlete_id = a.athlete_id
            LEFT JOIN equipment_summary es ON es.athlete_id = a.athlete_id
            LEFT JOIN sponsorship_summary ss ON ss.athlete_id = a.athlete_id
            ORDER BY a.lastname ASC, a.firstname ASC
        """)
        return _dict_rows(cur)
    except psycopg2.Error as sqle:
        print("psycopg2.Error : " + str(sqle))
        return None
    finally:
        if cur is not None:
            cur.close()
        conn.close()

"""
    Search for trials.

    If search_by_username is False:
        - Perform a case-insensitive search on athlete full name, official full name, event/trial name, or trial date (DD-MM-YYYY).

    If search_by_username is True:
        - Perform a case-insensitive search by athlete username only.
"""
def findTrials(keyword, search_by_username=False):
    conn = openConnection()
    if conn is None:
        return None

    cur = None
    try:
        cur = conn.cursor()
        base_select = """
            SELECT
                t.trial_id,
                t.trial_name,
                to_char(t.trial_date, 'DD-MM-YYYY') AS trial_date,
                a.firstname || ' ' || a.lastname AS athlete,
                a.username AS athlete_username,
                CASE WHEN p.is_winner THEN 'Yes' ELSE 'No' END AS is_winner,
                o.firstname || ' ' || o.lastname AS official,
                o.username AS official_username,
                COALESCE(NULLIF(p.performance_note, ''), 'N/A') AS performance_note,
                t.trial_date AS sort_trial_date,
                p.status
            FROM participation p
            JOIN athlete a ON a.athlete_id = p.athlete_id
            JOIN trials t ON t.trial_id = p.trial_id
            JOIN official o ON o.official_id = p.official_id
        """

        if search_by_username:
            cur.execute(base_select + """
                WHERE lower(a.username) = lower(%s)
                ORDER BY t.trial_id
            """, (keyword,))
        else:
            search_keyword = '%' + keyword + '%'
            cur.execute(base_select + """
                WHERE NOT (
                    p.status = 'completed'
                    AND t.trial_date < CURRENT_DATE - INTERVAL '3 years'
                )
                  AND (
                    a.firstname || ' ' || a.lastname ILIKE %s
                    OR t.trial_name ILIKE %s
                    OR to_char(t.trial_date, 'DD-MM-YYYY') ILIKE %s
                    OR COALESCE(p.performance_note, '') ILIKE %s
                    OR o.firstname || ' ' || o.lastname ILIKE %s
                  )
                ORDER BY
                    CASE WHEN t.trial_date >= CURRENT_DATE AND p.status = 'scheduled' THEN 0 ELSE 1 END,
                    t.trial_date ASC,
                    t.trial_name ASC
            """, (search_keyword, search_keyword, search_keyword, search_keyword, search_keyword))

        rows = _dict_rows(cur)
        for row in rows:
            del row['sort_trial_date']
            del row['status']
        return rows
    except psycopg2.Error as sqle:
        print("psycopg2.Error : " + str(sqle))
        return None
    finally:
        if cur is not None:
            cur.close()
        conn.close()

"""
    Adds a new trial participation record to the database.
"""
def addTrialParticipation(athlete_username, trial_name, trial_date, official_username):
    conn = openConnection()
    if conn is None:
        return False

    cur = None
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT itm_add_trial_participation(%s, %s, %s::date, %s)
        """, (athlete_username, trial_name, trial_date, official_username))
        success = cur.fetchone()[0]
        if success:
            conn.commit()
            return True
        conn.rollback()
        return False
    except psycopg2.Error as sqle:
        print("psycopg2.Error : " + str(sqle))
        conn.rollback()
        return False
    finally:
        if cur is not None:
            cur.close()
        conn.close()

"""
    Updates a trial participation record in the database.
"""
def updateTrialParticipation(trial_id, athlete_usernmae, is_winner, officials_update, performance_note):
    conn = openConnection()
    if conn is None:
        return False

    cur = None
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT itm_update_trial_result(%s::int, %s, %s::boolean, %s, %s)
        """, (
            trial_id,
            athlete_usernmae,
            _normalise_winner(is_winner),
            officials_update,
            performance_note
        ))
        success = cur.fetchone()[0]
        if success:
            conn.commit()
            return True
        conn.rollback()
        return False
    except psycopg2.Error as sqle:
        print("psycopg2.Error : " + str(sqle))
        conn.rollback()
        return False
    finally:
        if cur is not None:
            cur.close()
        conn.close()

def updateTrialResult(trial_id, athlete_username, is_winner, officials_update, performance_note):
    return updateTrialParticipation(trial_id, athlete_username, is_winner, officials_update, performance_note)
