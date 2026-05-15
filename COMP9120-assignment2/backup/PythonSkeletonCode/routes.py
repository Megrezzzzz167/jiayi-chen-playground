# Importing the frameworks
from flask import *
from datetime import datetime
import database

user_details = {}
session = {}
page = {}

# Initialise the application
app = Flask(__name__)
app.secret_key = 'aab12124d346928d14710610f'


#####################################################
##  INDEX
#####################################################

@app.route('/')
def index():
    # Check if the user is logged in
    if('logged_in' not in session or not session['logged_in']):
        return redirect(url_for('login'))
    page['title'] = 'IOMC'
    
    return redirect(url_for('summary'))

    #return render_template('index.html', session=session, page=page, user=user_details)

#####################################################
##  LOGIN
#####################################################

@app.route('/login', methods=['POST', 'GET'])
def login():
    # Check if they are submitting details, or they are just logging in
    if (request.method == 'POST'):
        # submitting details
        login_return_data = check_login(request.form['id'], request.form['password'])

        # If they have incorrect details
        if login_return_data is None:
            page['bar'] = False
            flash("Incorrect login info, please try again.")
            return redirect(url_for('login'))

        # Log them in
        page['bar'] = True
        welcomestr = 'Welcome back, ' + login_return_data['firstName'] + ' ' + login_return_data['lastName']
        flash(welcomestr)
        session['logged_in'] = True

        # Store the user details
        global user_details
        user_details = login_return_data
        return redirect(url_for('index'))

    elif (request.method == 'GET'):
        return(render_template('login.html', page=page))

#####################################################
##  LOGOUT
#####################################################

@app.route('/logout')
def logout():
    session['logged_in'] = False
    page['bar'] = True
    flash('You have been logged out. See you soon!')
    return redirect(url_for('index'))

#####################################################
##  Summary
#####################################################
@app.route('/summary', methods=['POST', 'GET'])
def summary():
    # Check if user is logged in
    if ('logged_in' not in session or not session['logged_in']):
        return redirect(url_for('login'))
    
    summary = database.getAthleteTrialsSummary()
    if (summary is None):
        summary = []
        flash("There are no summary in the system")
        page['bar'] = False
    return render_template('summary.html', summary=summary, session=session, page=page)

#####################################################
##  Find Trials 
#####################################################
@app.route('/find_trials', methods=['POST', 'GET'])
def find_trials():
    # Check if user is logged in
    if ('logged_in' not in session or not session['logged_in']):
        return redirect(url_for('login'))

    trial_list_find = []

    # -------- GET: clicking a row --------
    if request.method == 'GET':
        username = request.args.get('username')
        if username:
            trial_list_find = database.findTrials(
                keyword=username, 
                search_by_username=True
            )

    # -------- POST: searching --------
    elif request.method == 'POST':
        search_term = request.form['search'].strip()

        if search_term == '':
            flash('Search field cannot be empty or contain only spaces.')
            page['bar'] = False
            return redirect(request.referrer)

        # print(search_term)
        trial_list_find = database.findTrials(
            keyword=search_term, 
            search_by_username=False
        )

        # Only show this for POST searches
        if not trial_list_find:
            flash('Searching did not return any results.')
            page['bar'] = False

    return render_template(
        'find_trials.html',
        trial_list=trial_list_find,
        session=session,
        page=page
    )

#####################################################
##  Add trial
#####################################################

@app.route('/new_participation' , methods=['GET', 'POST'])
def new_participation():
    # Check if the user is logged in
    if ('logged_in' not in session or not session['logged_in']):
        return redirect(url_for('login'))

    # If we're just looking at the 'new trial' page
    if(request.method == 'GET'):
        times = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]
        return render_template('new_participation.html', user=user_details, times=times, session=session, page=page)

	# If we're adding a new record
    success = database.addTrialParticipation(request.form['athlete_username'],
                                            request.form['trial_name'],
                                            request.form['trial_date'],
                                            request.form['official_username'])
    if(success == True):
        page['bar'] = True
        flash("New Trial Participation added!")
        return(redirect(url_for('index')))
    else:
        page['bar'] = False
        flash("There was an error adding a participation.")
        return(redirect(url_for('new_participation')))

#####################################################
## Update Trial
#####################################################
@app.route('/update_participation', methods=['GET', 'POST'])
def update_participation():
    # Check if the user is logged in
    if ('logged_in' not in session or not session['logged_in']):
        return redirect(url_for('login'))

    # If we're just looking at the 'update trial' page
    if (request.method == 'GET'):
        # Get the trial
        participation = {
            'trial_id': request.args.get('trial_id'),
            'trial_name': request.args.get('trial_name'),
            'athlete': request.args.get('athlete'),
            'athlete_username': request.args.get('athlete_username'),
            'official_username': request.args.get('official_username'),
			'performance_note': request.args.get('performance_note'),
            'is_winner' : request.args.get('is_winner')
        }

        # If there is no trial
        if participation['trial_id'] is None:
            participation = []
		    # Do not allow viewing if there is no admission to update
            page['bar'] = False
            flash("You do not have access to update that record!")
            return(redirect(url_for('index')))

	    # Otherwise, if admission details can be retrieved
        times = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]
        return render_template('update_participation.html', participationInfo=participation, user=user_details, times=times, session=session, page=page)

    # If we're updating

    success = database.updateTrialParticipation(request.form['trial_id'],
                                                request.form['athlete_username'],
                                                request.form['is_winner'],
                                                request.form['official_username'],
                                                request.form['performance_note'])
    if (success == True):
        page['bar'] = True
        flash("Trial record updated!")
        return(redirect(url_for('index')))
    else:
        page['bar'] = False
        flash("There was an error updating the trial.")
        return(redirect(url_for('index')))


def check_login(login, password):
    userInfo = database.checkLogin(login, password)

    if userInfo is None:
        return None
    else:
        tuples = {
            'login': userInfo[0],
            'firstName': userInfo[1],
            'lastName': userInfo[2]
        }
        return tuples
