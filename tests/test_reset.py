from pathlib import Path

def test_reset_recreates_volumes():
    reset=(Path(__file__).parents[1]/'scripts'/'reset.sh').read_text()
    assert 'docker compose down -v' in reset
    assert 'docker compose up --build -d' in reset
