RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'

BGREEN='\033[1;32m'       # Bold Green
BRED='\033[1;31m'         # Bold Red

NC='\033[0m' # No Color


new(){ echo -e "${BLUE}[NEW]${NC} $1"; }
warn(){ echo -e "${MAGENTA}[WARNING]${NC} $1"; }
info(){ echo -e "${ORANGE}[INFO]${NC} $1"; }
error(){ echo -e "${RED}[ERROR]${NC} $1"; }
ok(){ echo -e "${GREEN}[OK]${NC} $1"; }
