from pathlib import Path

ROOT=Path(__file__).parents[1]
def test_schema_covers_required_tables():
    sql=(ROOT/'database'/'init.sql').read_text()
    for table in ['users','drivers','cars','modifications','builds','build_modifications','race_events','race_entries','telemetry','workshop_jobs','audit_logs','flags']:
        assert f'CREATE TABLE {table}' in sql

def test_seed_has_four_flags_and_relationships():
    seed=(ROOT/'database'/'seed.sql').read_text()
    assert "'search'" in seed and "'union'" in seed and "'blind'" in seed and "'remediation'" in seed
    assert 'INSERT INTO build_modifications' in seed and 'INSERT INTO race_entries' in seed
