FROM python:3.11-slim

WORKDIR /app
COPY services /app/services

RUN pip install --no-cache-dir -r /app/services/worker/requirements.txt

CMD ["python", "-m", "services.worker.main"]
