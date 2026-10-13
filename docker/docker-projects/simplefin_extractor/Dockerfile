FROM python:3.12-slim

ENV TZ=America/Chicago \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN groupadd --gid 10001 extractor \
 && useradd --uid 10001 --gid extractor --no-create-home --shell /usr/sbin/nologin extractor

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY extract.py .

USER extractor
ENTRYPOINT ["python", "/app/extract.py"]
