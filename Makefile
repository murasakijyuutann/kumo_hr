.PHONY: up down logs migrate test reset-db
up:
		docker compose up -d --build

down:
		docker compose down

logs:
		docker compose logs -f backend frontend

migrate:
		docker compose exec backend python manage.py migrate

test:
		docker compose exec backend pytest
		docker compose exec frontend npm test

reset-db:
		docker compose down -v
		$(MAKE) up
