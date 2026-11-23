from contextlib import contextmanager
import logging
import psycopg2
from psycopg2.extras import RealDictCursor
from functools import wraps
from flask import Flask, abort, flash, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash
from config import DATABASE_URL, SECRET_KEY
from lab_diagnostics import lab_bp

app = Flask(__name__)
app.config["SECRET_KEY"] = SECRET_KEY
app.register_blueprint(lab_bp)
logging.basicConfig(level=logging.INFO)

@contextmanager
def db():
    conn = psycopg2.connect(DATABASE_URL)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

def rows(sql, params=None):
    with db() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        return cur.fetchall()

def execute(sql, params=None):
    with db() as conn, conn.cursor() as cur:
        cur.execute(sql, params)

def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if 'user' not in session:
            flash('Sign in to access team communications.', 'error')
            return redirect(url_for('login'))
        return view(*args, **kwargs)
    return wrapped

def crew_required(view):
    @wraps(view)
    @login_required
    def wrapped(*args, **kwargs):
        if session['user']['user_type'] != 'crew':
            abort(403)
        return view(*args, **kwargs)
    return wrapped

@app.context_processor
def inject_session_user():
    return {'session_user': session.get('user')}

@app.get("/")
def index():
    stats = rows("SELECT (SELECT count(*) FROM cars) AS cars, (SELECT count(*) FROM builds) AS builds, (SELECT count(*) FROM race_events) AS events, (SELECT count(*) FROM workshop_jobs WHERE status <> 'Complete') AS jobs")[0]
    next_event = rows("SELECT name,circuit,event_date,status FROM race_events ORDER BY event_date LIMIT 1")[0]
    fleet = rows("SELECT car_code,status,power_hp,total_km FROM cars ORDER BY id")
    jobs = rows("SELECT job_code,status,description FROM workshop_jobs ORDER BY CASE status WHEN 'In progress' THEN 0 WHEN 'Queued' THEN 1 ELSE 2 END, id LIMIT 3")
    bulletin = rows("SELECT u.display_name,m.body,m.created_at FROM team_messages m JOIN users u ON u.id=m.author_id ORDER BY m.created_at DESC LIMIT 3")
    return render_template("index.html", stats=stats, next_event=next_event, fleet=fleet, jobs=jobs, bulletin=bulletin)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username', '').strip().lower()
        password = request.form.get('password', '')
        user = rows('SELECT id, username, display_name, role_name, user_type, password_hash FROM users WHERE username=%s AND active=true', (username,))
        if user and check_password_hash(user[0]['password_hash'], password):
            record = user[0]
            session.clear()
            session['user'] = {key: record[key] for key in ('id', 'username', 'display_name', 'role_name', 'user_type')}
            flash(f"Welcome back, {record['display_name']}.", 'success')
            return redirect(url_for('index'))
        flash('Incorrect username or password.', 'error')
    return render_template('login.html')

@app.post('/logout')
def logout():
    session.clear()
    flash('You have been signed out.', 'success')
    return redirect(url_for('index'))

@app.route('/team-chat', methods=['GET', 'POST'])
@login_required
def team_chat():
    if request.method == 'POST':
        message = request.form.get('message', '').strip()
        if not message or len(message) > 500:
            flash('Messages must be between 1 and 500 characters.', 'error')
        else:
            execute('INSERT INTO team_messages (author_id, body) VALUES (%s, %s)', (session['user']['id'], message))
            flash('Message sent.', 'success')
        return redirect(url_for('team_chat'))
    messages = rows('SELECT u.display_name,u.role_name,u.user_type,m.body,m.created_at FROM team_messages m JOIN users u ON u.id=m.author_id ORDER BY m.created_at DESC LIMIT 40')
    return render_template('team_chat.html', messages=list(reversed(messages)))

@app.get("/cars")
def cars(): return render_template("cars.html", cars=rows("SELECT c.*, d.display_name driver FROM cars c LEFT JOIN drivers d ON d.id=c.primary_driver_id ORDER BY c.id"))

@app.route('/garage/manage', methods=['GET', 'POST'])
@crew_required
def garage_manage():
    if request.method == 'POST':
        action = request.form.get('action', 'update')
        if action == 'create':
            car_code = request.form.get('car_code', '').strip()
            model = request.form.get('model', '').strip()
            manufacturer = request.form.get('manufacturer', '').strip()
            model_year = request.form.get('model_year', type=int)
            powertrain = request.form.get('powertrain', '').strip()
            image_url = request.form.get('image_url', '').strip() or 'https://images.unsplash.com/photo-1492144534655-ae79c964c9d7?auto=format&fit=crop&w=1200&q=85'
            power_hp = request.form.get('power_hp', type=int)
            weight_kg = request.form.get('weight_kg', type=int)
            top_speed = request.form.get('top_speed_kph', type=int)
            primary_driver_id = request.form.get('primary_driver_id', type=int)
            driver_exists = primary_driver_id is None or bool(rows('SELECT 1 FROM drivers WHERE id=%s', (primary_driver_id,)))
            if not all((car_code, model, manufacturer, model_year, powertrain, power_hp, weight_kg, top_speed)) or not (1900 <= model_year <= 2100 and 100 <= power_hp <= 2000 and 500 <= weight_kg <= 5000 and 100 <= top_speed <= 500) or not driver_exists:
                flash('Complete all vehicle fields with realistic values.', 'error')
            else:
                try:
                    execute('INSERT INTO cars (car_code,model,manufacturer,model_year,powertrain,image_url,power_hp,weight_kg,top_speed_kph,total_km,primary_driver_id,status) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,0,%s,%s)', (car_code,model,manufacturer,model_year,powertrain,image_url,power_hp,weight_kg,top_speed,primary_driver_id,'Workshop'))
                    execute('INSERT INTO audit_logs (actor, action) VALUES (%s, %s)', (session['user']['username'], f'Added vehicle {car_code}'))
                    flash('New vehicle added to the workshop intake queue.', 'success')
                except psycopg2.IntegrityError:
                    flash('A vehicle with that display code already exists.', 'error')
            return redirect(url_for('garage_manage'))
        car_id = request.form.get('car_id', type=int)
        status = request.form.get('status', '').strip()
        power_hp = request.form.get('power_hp', type=int)
        total_km = request.form.get('total_km', type=int)
        primary_driver_id = request.form.get('primary_driver_id', type=int)
        if not car_id or status not in ('Track ready', 'Dyno review', 'Workshop') or power_hp is None or total_km is None or power_hp < 100 or total_km < 0:
            flash('Use a valid status, power figure, and kilometre reading.', 'error')
        else:
            if primary_driver_id is not None and not rows('SELECT 1 FROM drivers WHERE id=%s', (primary_driver_id,)):
                flash('Select a valid driver assignment.', 'error')
            else:
                execute('UPDATE cars SET status=%s, power_hp=%s, total_km=%s, primary_driver_id=%s WHERE id=%s', (status, power_hp, total_km, primary_driver_id, car_id))
                execute('INSERT INTO audit_logs (actor, action) VALUES (%s, %s)', (session['user']['username'], f'Updated vehicle #{car_id} and driver assignment'))
                flash('Vehicle status and driver assignment updated.', 'success')
        return redirect(url_for('garage_manage'))
    return render_template('garage_manage.html', cars=rows('SELECT c.id,c.car_code,c.status,c.power_hp,c.total_km,c.weight_kg,c.top_speed_kph,c.primary_driver_id,d.display_name driver_name FROM cars c LEFT JOIN drivers d ON d.id=c.primary_driver_id ORDER BY c.id'), drivers=rows('SELECT id,display_name,competition_class FROM drivers ORDER BY display_name'))

@app.get("/builds")
def builds(): return render_template("builds.html", builds=rows("SELECT b.id,b.build_code,b.name,b.status,b.restricted,c.car_code FROM builds b JOIN cars c ON c.id=b.car_id WHERE b.restricted=false ORDER BY b.id"))

@app.get("/builds/search")
def build_search():
    query = request.args.get("query", "").strip()
    results = []
    if query:
        # Intentionally vulnerable, isolated training route. Do not copy into production.
        sql = "SELECT b.id,b.build_code,b.name,b.status,c.car_code,COALESCE(b.notes,'') AS notes FROM builds b JOIN cars c ON c.id=b.car_id WHERE b.restricted=false AND (b.name ILIKE '%" + query + "%' OR b.build_code ILIKE '%" + query + "%') ORDER BY b.id"
        try: results = rows(sql)
        except Exception: app.logger.info("Search query rejected by database"); results = []
    return render_template("build_search.html", query=query, results=results)

@app.get("/builds/view")
def build_view():
    build_id = request.args.get("id", "")
    if not build_id: return render_template("build_view.html", record=None)
    # Intentionally vulnerable lab route: six columns enable controlled UNION reasoning.
    sql = "SELECT b.id,b.build_code,b.name,b.status,c.car_code,COALESCE(b.notes,'') FROM builds b JOIN cars c ON c.id=b.car_id WHERE b.id=" + build_id
    try: record = rows(sql)
    except Exception: return render_template("build_view.html", record=None, error="Build record unavailable."), 400
    return render_template("build_view.html", record=record)

@app.get("/telemetry")
def telemetry(): return render_template("telemetry.html", sessions=rows("SELECT session_code, car_code, circuit, recorded_at FROM telemetry ORDER BY recorded_at DESC LIMIT 6"))

@app.get("/telemetry/check")
def telemetry_check():
    session = request.args.get("session", "")
    # Intentional boolean-based SQLi oracle. It reveals only whether a row matches.
    sql = "SELECT 1 FROM telemetry WHERE session_code='" + session + "' LIMIT 1"
    try: found = bool(rows(sql))
    except Exception: found = False
    return render_template("telemetry_check.html", found=found), (200 if found else 404)

@app.get("/events")
def events(): return render_template("events.html", events=rows("SELECT name,circuit,event_date,status FROM race_events ORDER BY event_date"))

@app.get('/race-centre')
def race_centre():
    events = rows('SELECT * FROM race_events ORDER BY event_date')
    entries = rows('SELECT e.name event_name,d.display_name,c.car_code,re.grid_position FROM race_entries re JOIN race_events e ON e.id=re.event_id JOIN drivers d ON d.id=re.driver_id JOIN cars c ON c.id=re.car_id ORDER BY e.event_date,re.grid_position')
    return render_template('race_centre.html', events=events, entries=entries)

@app.get('/race-maps')
def race_maps(): return render_template('race_maps.html')

@app.get("/drivers")
def drivers(): return render_template("drivers.html", drivers=rows("SELECT * FROM drivers ORDER BY display_name"))

@app.route('/drivers/manage', methods=['GET', 'POST'])
@login_required
def driver_manage():
    user = session['user']
    if request.method == 'POST':
        action = request.form.get('action', 'update')
        if action == 'create':
            if user['user_type'] != 'crew': abort(403)
            display_name = request.form.get('display_name', '').strip()
            nationality = request.form.get('nationality', '').strip()
            competition_class = request.form.get('competition_class', '').strip()
            username = request.form.get('username', '').strip().lower()
            password = request.form.get('password', '')
            if not all((display_name,nationality,competition_class,username)) or len(username) > 50 or len(password) < 10:
                flash('Provide full driver details and a password of at least 10 characters.', 'error')
            else:
                try:
                    with db() as conn, conn.cursor() as cur:
                        cur.execute('INSERT INTO drivers (display_name,nationality,competition_class) VALUES (%s,%s,%s) RETURNING id', (display_name,nationality,competition_class))
                        driver_id = cur.fetchone()[0]
                        cur.execute('INSERT INTO users (username,display_name,role_name,user_type,password_hash,driver_id) VALUES (%s,%s,%s,%s,%s,%s)', (username,display_name,'Driver','racer',generate_password_hash(password),driver_id))
                        cur.execute('INSERT INTO audit_logs (actor, action) VALUES (%s, %s)', (user['username'], f'Added driver {display_name}'))
                    flash('Driver account and profile created.', 'success')
                except psycopg2.IntegrityError:
                    flash('That driver callsign is already assigned.', 'error')
            return redirect(url_for('driver_manage'))
        driver_id = request.form.get('driver_id', type=int)
        starts = request.form.get('race_starts', type=int)
        podiums = request.form.get('podiums', type=int)
        wins = request.form.get('wins', type=int)
        best_lap = request.form.get('best_lap_ms', type=int)
        permitted = user['user_type'] == 'crew' or (user['user_type'] == 'racer' and driver_id == rows('SELECT driver_id FROM users WHERE id=%s', (user['id'],))[0]['driver_id'])
        if not permitted:
            abort(403)
        if None in (driver_id, starts, podiums, wins, best_lap) or min(starts, podiums, wins, best_lap) < 0 or wins > podiums or podiums > starts:
            flash('Stats must be valid: wins ≤ podiums ≤ race starts.', 'error')
        else:
            execute('UPDATE drivers SET race_starts=%s,podiums=%s,wins=%s,best_lap_ms=%s WHERE id=%s', (starts,podiums,wins,best_lap,driver_id))
            execute('INSERT INTO audit_logs (actor, action) VALUES (%s, %s)', (user['username'], f'Updated driver #{driver_id} performance stats'))
            flash('Driver performance statistics updated.', 'success')
        return redirect(url_for('driver_manage'))
    if user['user_type'] == 'racer':
        drivers = rows('SELECT d.* FROM drivers d JOIN users u ON u.driver_id=d.id WHERE u.id=%s', (user['id'],))
    else:
        drivers = rows('SELECT * FROM drivers ORDER BY display_name')
    return render_template('driver_manage.html', drivers=drivers)

@app.get("/modifications")
def modifications(): return render_template("simple_list.html", title="Modification catalogue", items=rows("SELECT name,category,description FROM modifications ORDER BY name"))

@app.get("/workshop")
def workshop(): return render_template("simple_list.html", title="Workshop queue", items=rows("SELECT job_code AS name,status AS category,description FROM workshop_jobs ORDER BY id"))

@app.get("/secure/builds/search")
def secure_search():
    query=request.args.get("query", "").strip()
    results=rows("SELECT b.id,b.build_code,b.name,b.status,c.car_code,COALESCE(b.notes,'') AS notes FROM builds b JOIN cars c ON c.id=b.car_id WHERE b.restricted=false AND (b.name ILIKE %s OR b.build_code ILIKE %s) ORDER BY b.id", (f"%{query}%", f"%{query}%")) if query else []
    return render_template("build_search.html", query=query, results=results, secure=True)

@app.errorhandler(500)
def controlled_error(_): return "Service temporarily unavailable.", 500

if __name__ == "__main__": app.run(host="0.0.0.0", port=8080)
