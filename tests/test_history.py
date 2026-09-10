import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock
import read_history as history

class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name) / 'notifications'
        (self.base / 'history').mkdir(parents=True)
        self.state = Path(self.temp.name) / 'dismissed.json'
        self.app = dict(key='slack', name='Slack', icon='slack', desktopId='slack', aliases=['Slack'], schemes=['slack'])
        self.apps = {'slack': self.app}

    def write(self, timestamp, app='Slack', folder='history', **extra):
        identifier = f'{timestamp}-1.json'
        row = dict(app=app, timestamp=timestamp, summary='Message', body='<b>Hello</b><br>world')
        row.update(extra)
        ((self.base / folder) if folder else self.base).joinpath(identifier).write_text(json.dumps(row))
        return identifier

    def read(self):
        return history.read_history(self.base, self.state, self.apps)

    def test_group_icon_order_and_text(self):
        self.write(10); self.write(20, app='slack'); self.write(15, app='Other')
        groups = self.read()
        self.assertEqual([g['app'] for g in groups], ['Slack', 'Other'])
        self.assertEqual([r['timestamp'] for r in groups[0]['items']], [20, 10])
        self.assertEqual(groups[0]['icon'], 'slack')
        self.assertEqual(groups[0]['items'][0]['body'], 'Hello\nworld')

    def test_clear_survives_archive_and_restart_but_new_items_remain(self):
        identifier = self.write(10, folder='')
        history.clear_ids([identifier], self.state)
        self.assertEqual(self.read(), [])
        (self.base / identifier).rename(self.base / 'history' / identifier)
        self.write(20)
        self.assertEqual([r['id'] for r in self.read()[0]['items']], ['20-1.json'])

    def test_clear_stack_and_all_leave_unselected_items(self):
        a, b, c = self.write(10), self.write(20), self.write(30, app='Other')
        history.clear_ids([a,b], self.state)
        self.assertEqual([g['app'] for g in self.read()], ['Other'])
        history.clear_ids([c], self.state)
        self.assertEqual(self.read(), [])

    def test_clear_rejects_paths(self):
        with self.assertRaises(ValueError): history.clear_ids(['../elsewhere'], self.state)
        self.assertFalse(self.state.exists())

    def test_deep_links_and_command_hints(self):
        self.assertEqual(history.destination({'execArgv': '["xdg-open", "slack://channel?id=123"]'}, self.app), 'slack://channel?id=123')
        self.assertEqual(history.destination({'url': 'https://example.com/page'}, self.app), 'https://example.com/page')
        for row in ({'execArgv': '["bash", "-c", "touch /tmp/bad"]'}, {'url':'file:///etc/passwd'}, {'url':'javascript:alert(1)'}, {'url':'unknown://foo'}):
            self.assertEqual(history.destination(row, self.app), '')

    def test_empty_sender_can_use_known_app_summary(self):
        self.write(10, app='', summary='Slack')
        self.assertEqual(self.read()[0]['app'], 'Slack')

    def test_live_copy_wins_over_archived_copy(self):
        self.write(10, summary='Archived')
        self.write(10, folder='', summary='Current')
        items = self.read()[0]['items']
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]['summary'], 'Current')

    def test_bad_files_do_not_hide_valid_notifications(self):
        self.write(10)
        for identifier, content in [('20-1.json', '{'), ('30-1.json', '[]'),
                                    ('40-1.json', '{"timestamp": "NaN"}'),
                                    ('not-an-id.json', '{}')]:
            (self.base / identifier).write_text(content)
        self.assertEqual([item['id'] for item in self.read()[0]['items']], ['10-1.json'])

    def test_only_newest_fifty_notifications_are_visible(self):
        for timestamp in range(60):
            self.write(timestamp)
        items = self.read()[0]['items']
        self.assertEqual(len(items), 50)
        self.assertEqual([item['timestamp'] for item in items], list(range(59, 9, -1)))

    def test_invalid_clear_payload_does_not_change_state(self):
        history.clear_ids(['10-1.json'], self.state)
        for invalid in ['10-1.json', [None], ['20-1.json'] * 501]:
            with self.assertRaises(ValueError):
                history.clear_ids(invalid, self.state)
        self.assertEqual(history.dismissed_ids(self.state), {'10-1.json'})

    @patch.object(history.subprocess, 'Popen')
    @patch.object(history.subprocess, 'run')
    def test_missing_notification_does_not_launch_anything(self, run, popen):
        self.assertFalse(history.activate('missing', [])['ok'])
        run.assert_not_called()
        popen.assert_not_called()

    @patch.object(history.subprocess, 'Popen')
    @patch.object(history.subprocess, 'run')
    def test_activation_focuses_running_app(self, run, popen):
        identifier = self.write(10)
        run.side_effect = [Mock(stdout=json.dumps([dict(address='0x123', **{'class':'Slack'})])), Mock(returncode=0)]
        self.assertEqual(history.activate(identifier,self.read())['action'], 'focus')
        self.assertIn('address:0x123', run.call_args_list[1].args[0][2])
        popen.assert_not_called()

    @patch.object(history.subprocess, 'Popen')
    @patch.object(history.subprocess, 'run')
    def test_activation_launches_closed_app(self, run, popen):
        identifier = self.write(10)
        run.return_value = Mock(stdout='[]')
        self.assertEqual(history.activate(identifier,self.read())['action'], 'launch')
        self.assertEqual(popen.call_args.args[0], ['/usr/bin/gtk-launch','slack'])

    @patch.object(history.subprocess, 'Popen')
    def test_activation_opens_explicit_deep_link(self, popen):
        identifier = self.write(10, url='slack://channel?id=123')
        self.assertEqual(history.activate(identifier,self.read())['action'], 'link')
        self.assertEqual(popen.call_args.args[0], ['/usr/bin/xdg-open','slack://channel?id=123'])

if __name__ == '__main__':
    unittest.main()
