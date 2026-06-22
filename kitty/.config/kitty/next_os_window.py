from kittens.tui.handler import result_handler


def main(args):
    pass


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    from kitty.fast_data_types import current_os_window

    ids = sorted(boss.os_window_map)  # ponytail: stable order = creation order
    if len(ids) < 2:
        return
    step = -1 if 'prev' in args else 1
    cur = current_os_window()
    i = ids.index(cur) if cur in ids else 0
    boss.focus_os_window(ids[(i + step) % len(ids)])
