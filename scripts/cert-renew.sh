#!/bin/bash
certbot renew --quiet --deploy-hook "nginx -s reload"
