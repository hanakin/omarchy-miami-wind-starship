#!/bin/sh

# Draws the whole top line of the prompt at exactly the terminal width. Every piece
# is measured, and pieces are dropped or shortened in order of importance until the
# line fits, so it never wraps at any width.

# Measure characters, not bytes, whatever locale the shell was started with.
LC_ALL="$(locale -a 2>/dev/null | awk 'tolower($0) ~ /^c\.utf-?8$/ { c = $0 } tolower($0) ~ /\.utf-?8$/ && !utf8 { utf8 = $0 } END { print c ? c : utf8 }')"
export LC_ALL

# Starship gives custom commands neither the width, the last exit status nor its
# duration; they exist only on the command line of the starship process that runs us.
pid=$PPID
while [ "${pid:-1}" -gt 1 ]; do
	if [ -r "/proc/$pid/comm" ]; then
		[ "$(cat "/proc/$pid/comm" 2>/dev/null)" = starship ] && break
		read -r _ _ _ pid _ <"/proc/$pid/stat" 2>/dev/null || pid=1
	else
		info="$(ps -ww -o ppid=,comm= -p "$pid" 2>/dev/null)" || break
		read -r parent comm <<EOF
$info
EOF
		[ "${comm##*/}" = starship ] && break
		pid="$parent"
	fi
done
if [ -r "/proc/$pid/cmdline" ]; then
	args="$(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null)"
else
	args="$(ps -ww -o args= -p "$pid" 2>/dev/null | tr '[:space:]' '\n')"
fi
arg() { printf '%s\n' "$args" | sed -n "s/^--$1=//p"; }
status="$(arg status)"
duration="$(arg cmd-duration)"
cols="${MIAMI_WIND_COLS:-$(arg terminal-width)}"
[ -n "$cols" ] || cols="$( (stty size </dev/tty) 2>/dev/null | cut -d' ' -f2)"
cols="${cols:-80}"
status="${status:-0}"
duration="${duration:-0}"

width() { printf '%s' "$1" | wc -m; }

# Glyphs
lead_icon="$(printf '\363\261\232\235')"
sep_r="$(printf '\356\202\260')"
sep_l="$(printf '\356\202\262')"
cap_r="$(printf '\356\202\264')"
branch_icon="$(printf '\357\220\230')"

# Colors
base_fg="30;30;46"
pink="244;114;182"
cyan="34;211;238"
git_bg="69;71;90"
green="52;211;153"
red="248;113;113"
orange="253;186;116"
blue="129;140;248"
purple="192;132;252"
yellow="254;240;138"
git_green="74;222;128"
git_yellow="254;240;138"
git_red="244;63;94"

# Left side: host and path

host="$(uname -n)"
host="${host%%.*}"

path="$PWD"
case "$path" in
	"$HOME") path="~" ;;
	"$HOME"/*) path="~${path#"$HOME"}" ;;
esac
path="$(printf '%s' "$path" | sed \
	-e "s|Documents|$(printf '\363\260\210\231') |g" \
	-e "s|Downloads|$(printf '\357\200\231') |g" \
	-e "s|Music|$(printf '\357\200\201') |g" \
	-e "s|Pictures|$(printf '\357\200\276') |g" \
	-e "s|Developer|$(printf '\363\260\262\213') |g")"
# Keep the last three directories, like Starship's truncation_length = 3.
path="$(printf '%s' "$path" | awk -F/ '{
	n = NF; if ($1 == "" && n > 1) n--
	if (n <= 3) { print; exit }
	printf "…"; for (i = NF - 2; i <= NF; i++) printf "/%s", $i; print ""
}')"

# Left side: git

in_git=0
branch=""
ahead=0 behind=0 staged=0 unstaged=0 untracked=0 conflicted=0 op_state=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	in_git=1
	branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)"
	status_lines="$(git status --porcelain=2 --branch 2>/dev/null)"
	while IFS= read -r line; do
		case "$line" in
			"# branch.ab "*)
				set -- $line
				ahead="${3#+}"
				behind="${4#-}"
				;;
			"1 "*|"2 "*)
				x="$(printf '%s' "$line" | cut -c3)"
				y="$(printf '%s' "$line" | cut -c4)"
				[ "$x" != "." ] && staged=$((staged + 1))
				[ "$y" != "." ] && unstaged=$((unstaged + 1))
				;;
			"u "*) conflicted=$((conflicted + 1)) ;;
			"? "*) untracked=$((untracked + 1)) ;;
		esac
	done <<EOF
$status_lines
EOF
	git_dir="$(git rev-parse --git-dir 2>/dev/null)"
	if [ -n "$git_dir" ]; then
		[ -d "$git_dir/rebase-merge" ] && op_state="rebase"
		[ -d "$git_dir/rebase-apply" ] && op_state="rebase"
		[ -f "$git_dir/MERGE_HEAD" ] && op_state="merge"
		[ -f "$git_dir/CHERRY_PICK_HEAD" ] && op_state="pick"
		[ -f "$git_dir/REVERT_HEAD" ] && op_state="revert"
		[ -f "$git_dir/BISECT_LOG" ] && op_state="bisect"
	fi
fi

branch_fg="$git_green"
if [ "$conflicted" -gt 0 ] || [ -n "$op_state" ]; then
	branch_fg="$git_red"
elif [ "$staged" -gt 0 ] || [ "$unstaged" -gt 0 ] || [ "$untracked" -gt 0 ] || [ "${ahead:-0}" -gt 0 ] || [ "${behind:-0}" -gt 0 ]; then
	branch_fg="$orange"
fi

# Counters as "color|text" lines, drawn in this order.
counters=""
add_counter() { [ "${2:-0}" -gt 0 ] 2>/dev/null && counters="$counters$1|$3$2
"; }
add_counter "$git_green" "$ahead" "$(printf '\342\207\241')"
add_counter "$git_green" "$staged" "+"
add_counter "$git_green" "$untracked" "?"
add_counter "$git_yellow" "$unstaged" "!"
add_counter "$git_red" "$behind" "$(printf '\342\207\243')"
add_counter "$git_red" "$conflicted" "~"
[ -n "$op_state" ] && counters="$counters$git_red|$op_state
"
counters_w="$(printf '%s' "$counters" | awk -F'|' 'NF { w += length($2) + 1 } END { print w + 0 }')"

# Right side: segments as "bg|text" lines, most important first. Display order is
# status, duration, languages and tools, then the clock last.

find_up() {
	dir="$PWD"
	while [ "$dir" != "/" ]; do
		[ -e "$dir/$1" ] && return 0
		dir="$(dirname "$dir")"
	done
	[ -e "/$1" ]
}

segment_python() {
	if find_up pyproject.toml || find_up requirements.txt || find_up Pipfile || find_up setup.py || find_up .python-version || find_up environment.yml || find_up .venv || [ -n "$VIRTUAL_ENV" ]; then
		ver="$(python3 --version 2>/dev/null | awk '{print $2}')"
		[ -n "$VIRTUAL_ENV" ] && venv="($(basename "$VIRTUAL_ENV"))" || venv=""
		[ -n "$ver" ] && printf ' \356\230\206 %s%s ' "$ver" "$venv"
	fi
}

segment_node() {
	if find_up package.json || find_up .nvmrc || find_up bun.lock || find_up bun.lockb || find_up pnpm-lock.yaml || find_up yarn.lock; then
		ver="$(node --version 2>/dev/null | sed 's/^v//')"
		[ -n "$ver" ] && printf ' \356\234\230 %s ' "$ver"
	fi
}

segment_rust() {
	if find_up Cargo.toml || find_up rust-toolchain || find_up rust-toolchain.toml; then
		ver="$(rustc --version 2>/dev/null | awk '{print $2}')"
		[ -n "$ver" ] && printf ' \356\236\250 %s ' "$ver"
	fi
}

segment_go() {
	if find_up go.mod || find_up go.work; then
		ver="$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//')"
		[ -n "$ver" ] && printf ' \356\230\247 %s ' "$ver"
	fi
}

segment_java() {
	if find_up pom.xml || find_up build.gradle || find_up build.gradle.kts || find_up gradlew || find_up .java-version; then
		ver="$(java -version 2>&1 | awk -F '"' 'NR==1{print $2}')"
		[ -n "$ver" ] && printf ' \356\211\226 %s ' "$ver"
	fi
}

segment_package() {
	dir="$PWD"
	pkg=""
	while [ "$dir" != "/" ]; do
		if [ -f "$dir/package.json" ]; then
			pkg="$dir/package.json"
			break
		fi
		dir="$(dirname "$dir")"
	done
	if [ -n "$pkg" ]; then
		ver="$(sed -n 's/.*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$pkg" | head -n 1)"
		[ -n "$ver" ] && printf ' \363\260\217\227 %s ' "$ver"
	fi
}

segment_docker() {
	if find_up Dockerfile || find_up docker-compose.yml || find_up docker-compose.yaml || [ -n "$DOCKER_CONTEXT" ]; then
		ctx="${DOCKER_CONTEXT:-$(docker context show 2>/dev/null)}"
		[ -n "$ctx" ] && printf ' \357\214\210 %s ' "$ctx"
	fi
}

if [ "$status" -eq 0 ] 2>/dev/null; then
	status_seg="$green|$(printf ' \357\200\214 ')"
else
	status_seg="$red|$(printf ' \357\200\215 %s ' "$status")"
fi
time_seg="$pink|$(printf ' \357\220\272 %s ' "$(date '+%I:%M %p')")"
duration_seg=""
[ "$duration" -ge 3000 ] 2>/dev/null && duration_seg="$orange|$(printf ' \357\211\222 %ss ' $((duration / 1000)))"

# Language and tool segments alternate purple and blue.
extras=""
lang_bg="$purple"
for seg in python node rust go java package; do
	text="$(segment_$seg)"
	[ -n "$text" ] || continue
	extras="$extras$lang_bg|$text
"
	[ "$lang_bg" = "$purple" ] && lang_bg="$blue" || lang_bg="$purple"
done
text="$(segment_docker)"
[ -n "$text" ] && extras="$extras$blue|$text
"
[ -n "$AWS_PROFILE" ] && extras="$extras$yellow|$(printf ' \363\260\270\217 %s ' "$AWS_PROFILE")
"
{ [ -n "$DIRENV_FILE" ] || [ -n "$DIRENV_DIR" ]; } && extras="$extras$cyan|$(printf ' \363\261\201\277 direnv ')
"

# Fit: measure, then drop or shorten one thing at a time until the line fits.

show_lead=1 show_host=1 show_status=1 show_time=1 show_duration=1 show_counters=1 show_git=$in_git
max_branch=$((cols / 4))
[ "$max_branch" -lt 12 ] && max_branch=12
[ "$(width "$branch")" -gt "$max_branch" ] && branch="$(printf '%s' "$branch" | cut -c1-$((max_branch - 1)))…"

segs_w() { printf '%s' "$1" | awk -F'|' 'NF { w += length($2) + 1 } END { print w + 0 }'; }

right_segs() {
	[ "$show_status" -eq 1 ] && printf '%s\n' "$status_seg"
	[ "$show_duration" -eq 1 ] && [ -n "$duration_seg" ] && printf '%s\n' "$duration_seg"
	printf '%s' "$extras"
	[ "$show_time" -eq 1 ] && printf '%s\n' "$time_seg"
}

total() {
	w=3
	[ "$show_lead" -eq 1 ] && w=$((w + 3))
	[ "$show_host" -eq 1 ] && w=$((w + $(width "$host") + 1))
	{ [ "$show_lead" -eq 1 ] || [ "$show_host" -eq 1 ]; } && w=$((w + 1))
	w=$((w + $(width "$path") + 2))
	if [ "$show_git" -eq 1 ]; then
		w=$((w + 1 + $(width "$branch") + 6 + 1))
		[ "$show_counters" -eq 1 ] && w=$((w + counters_w))
	else
		w=$((w + 1))
	fi
	r="$(right_segs)"
	[ -n "$r" ] && w=$((w + $(segs_w "$r") + 1))
	echo "$w"
}

# Shorten text from the left to n characters, marking the cut with "…".
cut_left() {
	[ "$2" -lt 1 ] && { printf '…'; return; }
	printf '%s' "$1" | awk -v n="$2" '{ print "…" substr($0, length($0) - n + 1) }'
}

step=0
over=$(($(total) - cols))
while [ "$over" -gt 0 ]; do
	step=$((step + 1))
	case "$step" in
		1|2|3|4|5|6|7|8|9)
			# Tool segments go first, the least important (last) one at a time.
			[ -n "$extras" ] && extras="$(printf '%s' "$extras" | sed '$d')" && [ -n "$extras" ] && extras="$extras
"
			;;
		10) show_duration=0 ;;
		11) show_time=0 ;;
		12) show_counters=0 ;;
		13)
			# Branch down to 8 characters.
			bw="$(width "$branch")"
			keep=$((bw - over))
			[ "$keep" -lt 8 ] && keep=8
			[ "$keep" -lt "$bw" ] && branch="$(printf '%s' "$branch" | cut -c1-$((keep - 1)))…"
			;;
		14)
			# Path down to its last directory.
			last="${path##*/}"
			[ "$last" != "$path" ] && path="…/$last"
			;;
		15) show_host=0 ;;
		16) show_status=0 ;;
		17) show_git=0 ;;
		18) show_lead=0 ;;
		19)
			# Whatever is left comes out of the path.
			pw="$(width "$path")"
			path="$(cut_left "$path" $((pw - over - 1)))"
			;;
		*) break ;;
	esac
	over=$(($(total) - cols))
done
# A later step can free more room than it needed; bring back what still fits.
for flag in show_counters show_time show_duration; do
	eval "[ \"\$$flag\" -eq 0 ]" || continue
	eval "$flag=1"
	[ "$(total)" -gt "$cols" ] && eval "$flag=0"
done
fill=$((cols - $(total)))
[ "$fill" -lt 0 ] && fill=0

# Draw

esc="$(printf '\033')"
out="${esc}[38;2;${pink}m░▒▓"
if [ "$show_lead" -eq 1 ] || [ "$show_host" -eq 1 ]; then
	out="$out${esc}[48;2;${pink};38;2;${base_fg}m"
	[ "$show_lead" -eq 1 ] && out="$out $lead_icon "
	[ "$show_host" -eq 1 ] && out="$out$host "
	out="$out${esc}[38;2;${pink};48;2;${cyan}m$sep_r"
else
	out="$out${esc}[48;2;${cyan}m"
fi
out="$out${esc}[38;2;${base_fg};48;2;${cyan}m $path "
if [ "$show_git" -eq 1 ]; then
	out="$out${esc}[38;2;${cyan};48;2;${git_bg}m$sep_r${esc}[38;2;${branch_fg}m  $branch_icon $branch  "
	if [ "$show_counters" -eq 1 ]; then
		out="$out$(printf '%s' "$counters" | while IFS='|' read -r fg text; do
			[ -n "$text" ] && printf '\033[38;2;%sm%s ' "$fg" "$text"
		done)"
	fi
	out="$out${esc}[0m${esc}[38;2;${git_bg}m$sep_r"
else
	out="$out${esc}[0m${esc}[38;2;${cyan}m$sep_r"
fi
out="$out${esc}[0m$(printf "%${fill}s" "")"

prev=""
segs="$(right_segs)"
while IFS='|' read -r bg text; do
	[ -n "$text" ] || continue
	if [ -z "$prev" ]; then
		out="$out${esc}[38;2;${bg}m$sep_l"
	else
		out="$out${esc}[38;2;${bg};48;2;${prev}m$sep_l"
	fi
	out="$out${esc}[48;2;${bg};38;2;${base_fg}m$text"
	prev="$bg"
done <<EOF
$segs
EOF
[ -n "$prev" ] && out="$out${esc}[0m${esc}[38;2;${prev}m$cap_r"
printf '%s\033[0m' "$out"
