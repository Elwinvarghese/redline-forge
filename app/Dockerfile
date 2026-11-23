FROM python:3.12-slim
WORKDIR /srv/forgetrack
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN useradd --system --no-create-home forge && chown -R forge:forge /srv/forgetrack
USER forge
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
