#!/usr/bin/env bash
# Provision WordPress Stable

set -eo pipefail

echo " * Custom site template provisioner ${VVV_SITE_NAME} - downloads and installs a copy of WP stable for testing, building client sites, etc"

# fetch the first host as the primary domain. If none is available, generate a default using the site name
DB_NAME=$(get_config_value 'db_name' "${VVV_SITE_NAME}")
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*]/}
DB_PREFIX=$(get_config_value 'db_prefix' 'wp_')
DOMAIN=$(get_primary_host "${VVV_SITE_NAME}".test)
PUBLIC_DIR=$(get_config_value 'public_dir' "web")
SITE_TITLE=$(get_config_value 'site_title' "${DOMAIN}")
WP_LOCALE=$(get_config_value 'locale' 'en_US')
WP_TYPE=$(get_config_value 'wp_type' "single")
WP_VERSION=$(get_config_value 'wp_version' 'latest')

echo -e $DB_NAME;
echo -e $DB_PREFIX;
echo -e $DOMAIN;
echo -e $PUBLIC_DIR;
echo -e $SITE_TITLE;
echo -e $WP_LOCALE;
echo -e $WP_TYPE;
echo -e $WP_VERSION;

PUBLIC_DIR_PATH="${VVV_PATH_TO_SITE}"
if [ ! -z "${PUBLIC_DIR}" ]; then
  PUBLIC_DIR_PATH="${PUBLIC_DIR_PATH}/${PUBLIC_DIR}"
fi
echo -e $PUBLIC_DIR_PATH;

# Make a database, if we don't already have one
setup_database() {
  echo -e " * Creating database '${DB_NAME}' (if it's not already there)"
  mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`"
  echo -e " * Granting the wp user priviledges to the '${DB_NAME}' database"
  mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO wp@localhost IDENTIFIED BY 'wp';"
  echo -e " * DB operations done."
}

setup_nginx_folders() {
  echo " * Setting up the log subfolder for Nginx logs"
  noroot mkdir -p "${VVV_PATH_TO_SITE}/log"
  noroot touch "${VVV_PATH_TO_SITE}/log/nginx-error.log"
  noroot touch "${VVV_PATH_TO_SITE}/log/nginx-access.log"
  echo " * Creating the public folder at '${PUBLIC_DIR}' if it doesn't exist already"
  noroot mkdir -p "${PUBLIC_DIR_PATH}"
}

copy_nginx_configs() {
  echo " * Copying the sites Nginx config template"
  if [ -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx-custom.conf" ]; then
    echo " * A vvv-nginx-custom.conf file was found"
    noroot cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx-custom.conf" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
  else
    echo " * Using the default vvv-nginx-default.conf, to customize, create a vvv-nginx-custom.conf"
    noroot cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx-default.conf" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
  fi

  echo " * Applying public dir setting to Nginx config"
  noroot sed -i "s#{vvv_public_dir}#/${PUBLIC_DIR}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

  LIVE_URL=$(get_config_value 'live_url' '')
  if [ ! -z "$LIVE_URL" ]; then
    echo " * Adding support for Live URL redirects to NGINX of the website's media"
    # replace potential protocols, and remove trailing slashes
    LIVE_URL=$(echo "${LIVE_URL}" | sed 's|https://||' | sed 's|http://||'  | sed 's:/*$::')

    redirect_config=$((cat <<END_HEREDOC
if (!-e \$request_filename) {
  rewrite ^/[_0-9a-zA-Z-]+(/app/uploads/.*) \$1;
}
if (!-e \$request_filename) {
  rewrite ^/app/uploads/(.*)\$ \$scheme://${LIVE_URL}/app/uploads/\$1 redirect;
}
END_HEREDOC

    ) |
    # pipe and escape new lines of the HEREDOC for usage in sed
    sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n\\1/g'
    )

    noroot sed -i -e "s|\(.*\){{LIVE_URL}}|\1${redirect_config}|" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
  else
    noroot sed -i "s#{{LIVE_URL}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
  fi
}