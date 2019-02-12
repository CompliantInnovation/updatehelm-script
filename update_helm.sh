#!/bin/sh

# Written by Luca Santarella
# 2019-02-12
# LucaSpera <luca@docspera.com>

# Colors
NC='\033[0m' # No Color
BLUE='\033[0:36m' # Blue

# Check for staged changes
die () {
    echo >&2 "$@"
    exit 1
}

[ "$#" -eq 3 ] || die "usage: update_helm [CHART_DIR] [DEPLOYMENT_NAME] [SSH_PRIVATE_KEY_PATH]";

CHART_DIR="$1";
DEPLOYMENT_NAME="$2";
SSH_PRIVATE_KEY_PATH="$3";
STATUS=$(git status -s -uno);

if ! [ "$STATUS" = "" ]; then 
	echo "Changes are staged. Please commit them or unstage them.";
	echo $STATUS;
	return 1;
fi

parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

# Parse chart YAML
eval $(parse_yaml "$PWD/$CHART_DIR/Chart.yaml" "chart_");
eval $(parse_yaml "$PWD/$CHART_DIR/values.yaml" "chart_values_");

# Send info to User
echo "${BLUE}Chart Directory:${NC} ./$CHART_DIR";
echo "${BLUE}Chart:${NC} $chart_name";
echo "${BLUE}Current Image:${NC} $chart_values_image_tag";

# Get current Git Commit to name as image tag
NEW_TAG=$(echo "$(git rev-parse --verify HEAD)" | cut -c 1-12)
echo "${BLUE}New Tag:${NC} $NEW_TAG";

NEW_IMAGE_URI="$chart_values_image_repository:$NEW_TAG"

echo "${BLUE}Building Docker image...${NC}";

# Build Docker Image
#docker build -t "$NEW_IMAGE_URI" --build-arg SSH_PRIVATE_KEY="$(cat $SSH_PRIVATE_KEY_PATH)" .

#echo "${BLUE}Pushing Docker image...${NC}";

# Push ECS image
#ecs-cli push "$NEW_IMAGE_URI"

# Update Chart values for new tag
echo "${BLUE}New Chart Values:${NC}";
cat "$PWD/$CHART_DIR/values.yaml" | docker run --rm -i jlordiales/jyparser set ".image.tag" \"$NEW_TAG\" | tee "$PWD/$CHART_DIR/values.yaml"

# Add the updated file
git add "$PWD/$CHART_DIR/values.yaml"

echo "${BLUE}Do you want to automatically commit this file? (y/n)${NC}"
read AUTO_COMMIT;

if [ "$AUTO_COMMIT" = "y" ]; then
	git commit -m "Auto Gen: Updated Helm tag from $chart_values_image_tag to $NEW_TAG";
fi

helm upgrade "$DEPLOYMENT_NAME" "$CHART_DIR" --recreate-pods

exit 0;