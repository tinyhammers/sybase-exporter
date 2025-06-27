#!/bin/bash
#
# Script to build the Sybase Prometheus Exporter RPM package
#

# Set version
VERSION="1.0.0"
NAME="sybase_exporter"

# Create build directories
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Create a temporary directory with the correct name
echo "Creating temporary directory..."
TEMP_DIR=$(mktemp -d)
PACKAGE_DIR="${TEMP_DIR}/${NAME}-${VERSION}"
mkdir -p "${PACKAGE_DIR}"

# Copy files to the temporary directory
echo "Copying files..."
cp -r sybase_exporter.sh sybase_exporter.service sybase_exporter.conf Makefile sybase_exporter.spec README.md "${PACKAGE_DIR}/"

# Create tarball
echo "Creating tarball..."
(cd "${TEMP_DIR}" && tar -czf ~/rpmbuild/SOURCES/${NAME}-${VERSION}.tar.gz ${NAME}-${VERSION})

# Clean up temporary directory
rm -rf "${TEMP_DIR}"

# Copy spec file
echo "Copying spec file..."
cp ${NAME}.spec ~/rpmbuild/SPECS/

# Build RPM
echo "Building RPM package..."
rpmbuild -ba ~/rpmbuild/SPECS/${NAME}.spec

# Check if build was successful
if [ $? -eq 0 ]; then
    echo "RPM package built successfully!"
    echo "The RPM package is located at: ~/rpmbuild/RPMS/noarch/${NAME}-${VERSION}-1*.rpm"
else
    echo "Failed to build RPM package."
    exit 1
fi

# List the built RPM
ls -l ~/rpmbuild/RPMS/noarch/${NAME}-${VERSION}-1*.rpm
