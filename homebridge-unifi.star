load("schema.star", "schema")
load("render.star", "render")
load("http.star", "http")
load("cache.star", "cache")
load("hash.star", "hash")

WIDTH = 64
HEIGHT = 32

AVATAR_CONFIGURATIONS = {
    #   column_align        row_align           per_row size
    1: ("center",           "center",           1,      HEIGHT),
    2: ("center",           "space_between",    2,      HEIGHT - 1),
    3: ("center",           "space_around",     3,      (64 - 2) // 3),
    4: ("space_between",    "space_evenly",     2,      HEIGHT // 2 - 1),
    5: ("space_between",    "space_evenly",     3,      HEIGHT // 2 - 1),
    6: ("space_between",    "space_evenly",     3,      HEIGHT // 2 - 1),
    7: ("space_between",    "space_evenly",     4,      HEIGHT // 2 - 1),
    8: ("space_between",    "space_between",    4,      HEIGHT // 2 - 1),
}

def avatar(url, size):
    return render.Image(src=image_data(url), height=size, width=size)

def image_data(url):
    cached = cache.get(url)
    if cached:
        return cached

    response = http.get(url)

    if response.status_code != 200:
        fail("Image not found", url)

    data = response.body()
    cache.set(url, data, ttl_seconds=60 * 60 * 24)

    return data

def clients_by_room(clients):
    rooms = {}
    for client in clients:
        room = client["room"]
        if room not in rooms:
            rooms[room] = []

        rooms[room].append(client)

    return sorted(
        [
            (
                room,
                sorted(clients, key=lambda client: client["owner"])
            )
            for room, clients in rooms.items()
        ],
        key=lambda r_c: -len(r_c[1]) # Rooms with more people first
    )

def client_image_urls(clients):
    return [
        client["image_url"]
        for client in clients
        if client.get("image_url")
    ]

def render_client(client, image_size):
    return render.Row(
        cross_align="center",
        children=[
            render.Padding(
                pad=(0,0,2,0),
                child=avatar(client["image_url"], image_size)
            ),
            render.Text(client["owner"])
        ]
    )

def render_room_name(room):
    return render.Text(room, color="#bbbbbb")

def render_clients(clients, pad_client=(0,0,0,0), image_size=8, scroll_direction="horizontal", **kwargs):
    return render.Marquee(
        scroll_direction=scroll_direction,
        child=(render.Row if scroll_direction == "horizontal" else render.Column)(
            children=[
                render.Padding(
                    pad=((0,0,0,0) if i == len(clients) - 1 else pad_client),
                    child=render_client(client, image_size)
                )
                for i, client in enumerate(clients)
            ]
        ),
        **kwargs,
    )

def render_room(room, clients, index, room_count):
    if room_count == 1:
        return render.Column(
            children=[
                render.Padding(
                    pad=(0,0,0,1),
                    child=render_room_name(room),
                ),
                render_clients(
                    clients,
                    scroll_direction="vertical",
                    height=HEIGHT-8-1,
                    pad_client=(0,0,0,1),
                    image_size=(10 if len(clients) <= 2 else 8)
                )
            ]
        )

    if room_count == 2 or (room_count == 3 and index == 0):
        return render.Column(
            children=[
                render_room_name(room),
                render_clients(
                    clients,
                    scroll_direction="horizontal",
                    width=WIDTH,
                    pad_client=(0,0,4,0)
                )
            ]
        )

    return render.Row(
        children=[
            render.Padding(
                pad=(0,0,2,0),
                child=render_room_name(room),
            ),
            render_clients(
                clients,
                scroll_direction="horizontal",
                width=WIDTH - len(room) * 5, # Not exact
                pad_client=(0,0,4,0)
            )
        ]
    )

def main(config):
    API_URL = config.get("api_url")
    USERNAME = config.get("username")
    PASSWORD = config.get("password")
    AVATARS_ONLY = config.bool("avatars_only")

    if not API_URL:
        return render.Root(
            child=render.Box(
                child=render.WrappedText("homebridge- unifi API not configured")
            )
        )

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
        image_urls = client_image_urls(clients)
        if not image_urls:
            return []

        column_align, row_align, per_row, size = AVATAR_CONFIGURATIONS.get(len(image_urls), AVATAR_CONFIGURATIONS[8])

        row = []
        rows = [row]
        for url in image_urls:
            if len(row) == per_row:
                if len(rows) * size + size > HEIGHT:
                    break

                row = []
                rows.append(row)

            row.append(url)

        return render.Root(
            child=render.Column(
                expanded=True,
                main_align=column_align,
                children=[
                    render.Row(
                        expanded=True,
                        main_align=row_align,
                        cross_align=column_align,
                        children=[avatar(url, size) for url in row]
                    )
                    for row in rows
                ]
            )
        )
    else:
        rooms = clients_by_room(clients)

        return render.Root(
            child=render.Column(
                expanded=True,
                children=[
                    render_room(room, clients, i, len(rooms))
                    for i, (room, clients) in enumerate(rooms)
                ]
            )
        )

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
        ],
    )
