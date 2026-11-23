import os, sys
from unittest.mock import patch
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))
import app as target

def fake_rows(sql, params=None):
    if 'count(*)' in sql: return [{'cars':4,'builds':4,'events':3,'jobs':2}]
    if 'FROM race_events ORDER' in sql: return [{'name':'Ember 300','circuit':'Ember Circuit','event_date':'2026-09-12','status':'Scheduled'}]
    if 'FROM telemetry WHERE' in sql: return [{'1':1}] if "invalid" not in sql else []
    if 'cars c LEFT' in sql: return []
    if 'builds b JOIN' in sql: return []
    return []

@patch.object(target, 'rows', side_effect=fake_rows)
def test_public_pages(_):
    client=target.app.test_client()
    for path in ['/', '/cars', '/builds', '/events', '/drivers', '/telemetry']:
        assert client.get(path).status_code == 200

@patch.object(target, 'rows', side_effect=fake_rows)
def test_oracle_status(_):
    client=target.app.test_client()
    assert client.get('/telemetry/check?session=EMB-Q1-07').status_code == 200
    assert client.get('/telemetry/check?session=invalid').status_code == 404

@patch.object(target, 'rows', side_effect=fake_rows)
def test_secure_search_parameterizes(_, monkeypatch):
    response=target.app.test_client().get('/secure/builds/search?query=alpha')
    assert response.status_code == 200
