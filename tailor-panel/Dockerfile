FROM php:8.3-apache

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev \
    && docker-php-ext-install pdo pdo_pgsql \
    && apt-get purge -y --auto-remove \
    && rm -rf /var/lib/apt/lists/*

# Apache en non-root : ecoute sur 8080 (>1024) et tourne en www-data.
RUN sed -i 's/Listen 80$/Listen 8080/' /etc/apache2/ports.conf \
    && sed -i 's#:80>#:8080>#' /etc/apache2/sites-available/000-default.conf \
    && chown -R www-data:www-data /var/run/apache2 /var/log/apache2 /var/www/html

COPY --chown=www-data:www-data index.php /var/www/html/index.php

USER www-data
EXPOSE 8080
