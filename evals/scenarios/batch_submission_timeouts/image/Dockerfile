FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /opt/batch-processor
COPY processor.py ./processor.py
RUN chmod -R a=rX /opt/batch-processor

USER 1001
EXPOSE 8080
ENTRYPOINT ["python3", "-u", "-m", "processor"]
