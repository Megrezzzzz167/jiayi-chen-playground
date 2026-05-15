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

    myHost = ""
    userid = ""
    passwd = ""
    
    # Create a connection to the database
    conn = None
    try:
        # Parses the config file and connects using the connect string
        conn = psycopg2.connect(database=userid,
                                    user=userid,
                                    password=passwd,
                                    host=myHost)

    except psycopg2.Error as sqle:
        print("psycopg2.Error : " + sqle.pgerror)
    
    # return the connection to use
    return conn

"""
    Checks the login credentials for an official user
"""
def checkLogin(login, password):
    return ['jdoe', 'John', 'Doe']

"""
    Retrieves a summary of each athlete's trials, including scheduled and completed trials, wins, equipment, sponsorship, and most recent trial date.
"""
def getAthleteTrialsSummary():
    return None

"""
    Search for trials.

    If search_by_username is False:
        - Perform a case-insensitive search on athlete full name, official full name, event/trial name, or trial date (DD-MM-YYYY).

    If search_by_username is True:
        - Perform a case-insensitive search by athlete username only.
"""
def findTrials(keyword, search_by_username=False):
    return None
    
"""
    Adds a new trial participation record to the database.
"""
def addTrialParticipation(athlete_username, trial_name, trial_date, official_username):
    return False

"""
    Updates a trial participation record in the database.
"""
def updateTrialParticipation(trial_id, athlete_usernmae, is_winner, officials_update, performance_note):
    return False
