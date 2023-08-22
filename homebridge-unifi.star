load("schema.star", "schema")
load("render.star", "render")
load("http.star", "http")
load("encoding/json.star", "json")
load("pixlib/input.star", "input")
load("./r.star", "r")

def clients_by_room(clients, room_aliases):
    rooms = {}
    for client in clients:
        room = client["room"]
        room = room_aliases.get(room, room)

        if room not in rooms:
            rooms[room] = []

        rooms[room].append(client)

    return sorted(
        [
            (
                room,
                sorted(clients, key=lambda client: client["display_name"])
            )
            for room, clients in rooms.items()
        ],
        key=lambda r_c: -len(r_c[1]) # Rooms with more people first. TODO: Longer room names first?
    )

def main(config):
    API_URL = config.get("api_url")
    USERNAME = config.get("username")
    PASSWORD = config.get("password")

    # Convert ROOM_ALIASES from `key1=value1;key2=value2` to `{"key1": "value1", "key2": "value2"}`
    ROOM_ALIASES = {
        alias.split("=")[0]: alias.split("=")[1]
        for alias
        in config.get("room_aliases", "").split(";")
    }

    AVATARS_ONLY = config.bool("avatars_only")
    EXTRA_AVATAR_URLS = config.get("extra_avatar_urls", "").split(",")

    INPUT = input.json()

    if INPUT:
        return render.Root(
            max_age=15000,
            child=r.event(INPUT)
        )

    if not API_URL:
        return render.Root(
            child=render.Box(
                child=render.WrappedText("homebridge- unifi API not configured")
            )
        )

    # TODO: Move to client.star
    def get_clients():
        response = http.get(API_URL + "/clients", auth=(USERNAME, PASSWORD))

        if response.status_code != 200:
            fail("Clients not found", response)

        return [
            client
            for client in response.json()
            if client["show_as_owner"]
        ]

    clients = get_clients()
    if not clients:
        return []

    if AVATARS_ONLY:
        image_urls = [
            client["image_url"]
            for client in clients
            if client.get("image_url")
        ]
        if EXTRA_AVATAR_URLS:
            image_urls.extend(EXTRA_AVATAR_URLS)

        if not image_urls:
            return []

        return render.Root(child=r.avatars(image_urls))

    rooms = clients_by_room(clients, ROOM_ALIASES)
    return render.Root(child=r.rooms(rooms))

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "api_url",
                name = "homebridge-unifi-occupancy Web Server URL",
                desc = "If HTTPS, certificate must be valid. Example: 'http://localhost:8582'",
                icon = "link"
            ),
            schema.Text(
                id = "username",
                name = "Username",
                desc = "",
                icon = "user",
            ),
            schema.Text(
                id = "password",
                name = "Password",
                desc = "",
                icon = "key",
            ),
            schema.Toggle(
                id = "avatars_only",
                name = "Show only avatars",
                desc = "Show a grid of avatars instead of rooms with names",
                icon = "face-smile",
                default = False,
            ),
            # TODO: room_aliases
            schema.Text(
                id = "extra_avatar_urls",
                name = "Extra avatar URLs",
                desc = "Comma-separated list of extra avatar URLs to show in the grid. Example: 'https://example.com/avatar1.png,https://example.com/avatar2.png'",
                icon = "key",
            ),
        ],
    )
