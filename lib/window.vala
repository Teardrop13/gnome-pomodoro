/*
 * Copyright (c) 2016 gnome-pomodoro contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 *
 */


namespace Pomodoro
{
    [GtkTemplate (ui = "/org/gnome/pomodoro/ui/window.ui")]
    public class Window : Gtk.ApplicationWindow, Gtk.Buildable
    {
        private static const int MIN_WIDTH = 540;
        private static const int MIN_HEIGHT = 700;

        private static const double FADED_IN = 1.0;
        private static const double FADED_OUT = 0.2;

        private static const double TIMER_LINE_WIDTH = 6.0;
        private static const double TIMER_RADIUS = 200.0;

        private struct Name
        {
            public string name;
            public string display_name;
        }

        private static const Name[] state_names = {
            { "null", "" },
            { "pomodoro", "Pomodoro" },
            { "short-break", "Short Break" },
            { "long-break", "Long Break" }
        };

        private static const GLib.ActionEntry[] action_entries = {
            { "start", on_start_activate },
            { "stop", on_stop_activate },
            { "pause", on_pause_activate },
            { "resume", on_resume_activate }
        };

        private unowned Pomodoro.Timer timer;

        [GtkChild]
        private Gtk.Stack stack;
        [GtkChild]
        private Gtk.ToggleButton state_togglebutton;
        [GtkChild]
        private Gtk.Label minutes_label;
        [GtkChild]
        private Gtk.Label seconds_label;
        [GtkChild]
        private Gtk.Widget timer_box;
        [GtkChild]
        private Gtk.Widget timer_frame;
        [GtkChild]
        private Gtk.Button pause_button;

        private Pomodoro.Animation blink_animation;

        construct
        {
            var geometry = Gdk.Geometry () {
                min_width = MIN_WIDTH,
                max_width = -1,
                min_height = MIN_HEIGHT,
                max_height = -1
            };
            var geometry_hints = Gdk.WindowHints.MIN_SIZE;
            this.set_geometry_hints (this,
                                     geometry,
                                     geometry_hints);

            this.add_action_entries (Window.action_entries, this);

            this.on_timer_state_notify ();
            this.on_timer_elapsed_notify ();
            this.on_timer_is_paused_notify ();
        }

        public void parser_finished (Gtk.Builder builder)
        {
            this.timer = Pomodoro.Timer.get_default ();

            base.parser_finished (builder);

            var state_togglebutton = builder.get_object ("state_togglebutton");
            state_togglebutton.bind_property ("active",
                                              builder.get_object ("state_popover"),
                                              "visible",
                                              GLib.BindingFlags.BIDIRECTIONAL);

            this.timer.notify["state"].connect_after (this.on_timer_state_notify);
            this.timer.notify["elapsed"].connect_after (this.on_timer_elapsed_notify);
            this.timer.notify["is-paused"].connect_after (this.on_timer_is_paused_notify);
        }

        private void on_blink_animation_complete ()
        {
            if (this.timer.is_paused) {
                this.blink_animation.start_with_value (1.0);
            }
        }

        private void on_timer_state_notify ()
        {
            this.stack.visible_child_name = 
                    (this.timer.state is Pomodoro.DisabledState) ? "disabled" : "enabled";

            foreach (var mapping in state_names)
            {
                if (mapping.name == this.timer.state.name) {
                    this.state_togglebutton.label = mapping.display_name;
                }
            }
        }

        private void on_timer_elapsed_notify ()
        {
            var remaining = (uint) double.max (Math.ceil (this.timer.remaining), 0.0);
            var minutes   = remaining / 60;
            var seconds   = remaining % 60;

            this.minutes_label.label = "%02u".printf (minutes);
            this.seconds_label.label = "%02u".printf (seconds);

            this.timer_frame.queue_draw ();
        }

        private void on_timer_is_paused_notify ()
        {
            if (this.blink_animation != null) {
                this.blink_animation.stop ();
                this.blink_animation = null;
            }

            if (this.timer.is_paused) {
                this.pause_button.label       = _("_Resume");
                this.pause_button.action_name = "win.resume";

                this.blink_animation = new Pomodoro.Animation (Pomodoro.AnimationMode.BLINK,
                                                               2500,
                                                               25);
                this.blink_animation.add_property (this.timer_box,
                                                   "opacity",
                                                   FADED_OUT);
                this.blink_animation.complete.connect (this.on_blink_animation_complete);
                this.blink_animation.start_with_value (1.0);
            }
            else {
                this.pause_button.label       = _("_Pause");
                this.pause_button.action_name = "win.pause";

                this.blink_animation = new Pomodoro.Animation (Pomodoro.AnimationMode.EASE_OUT,
                                                               200,
                                                               50);
                this.blink_animation.add_property (this.timer_box,
                                                   "opacity",
                                                   1.0);
                this.blink_animation.start ();
            }
        }

        [GtkCallback]
        private bool on_stack_draw (Gtk.Widget    widget,
                                    Cairo.Context context)
        {
            var style_context = widget.get_style_context ();
            var color         = style_context.get_color (widget.get_state_flags ());

            var width  = widget.get_allocated_width ();
            var height = widget.get_allocated_height ();
            var x      = 0.5 * width;
            var y      = 0.5 * height;

            context.set_line_width (TIMER_LINE_WIDTH);
            context.set_source_rgba (color.red,
                                     color.green,
                                     color.blue,
                                     color.alpha * 0.1);
            context.arc (x, y, TIMER_RADIUS, 0.0, 2 * Math.PI);
            context.stroke ();

            return false;
        }

        [GtkCallback]
        private bool on_timer_frame_draw (Gtk.Widget    widget,
                                          Cairo.Context context)
        {
            if (!(this.timer.state is Pomodoro.DisabledState))
            {
                var style_context = widget.get_style_context ();
                var color         = style_context.get_color (widget.get_state_flags ());

                var width  = widget.get_allocated_width ();
                var height = widget.get_allocated_height ();
                var x      = 0.5 * width;
                var y      = 0.5 * height;
                var progress = this.timer.state_duration > 0.0
                        ? this.timer.elapsed / this.timer.state_duration : 0.0;

                var angle1 = - 0.5 * Math.PI;
                var angle2 = - 0.5 * Math.PI + 2.0 * Math.PI * progress;

                context.set_line_width (TIMER_LINE_WIDTH);
                context.set_line_cap (Cairo.LineCap.ROUND);
                context.set_source_rgba (color.red,
                                         color.green,
                                         color.blue,
                                         color.alpha * FADED_IN - (color.alpha * 0.1) * (1.0 - FADED_IN));

                context.arc (x, y, TIMER_RADIUS, angle1, angle2);
                context.stroke ();
            }

            return false;
        }

        [GtkCallback]
        private void on_state_button_clicked (Gtk.Button button)
        {
            var timer_state = Pomodoro.TimerState.lookup (button.name);

            if (timer_state != null) {
                this.timer.state = timer_state;
            }
            else {
                GLib.critical ("Unknown timer state \"%s\"", button.name);
            }
        }

        [GtkCallback]
        private bool on_button_press (Gtk.Widget      widget,
                                      Gdk.EventButton event)
        {
            if (event.button == 1) {
                this.begin_move_drag ((int) event.button, (int) event.x_root, (int) event.y_root, event.time);

                return true;
            }

            return false;
        }

        private void on_start_activate (GLib.SimpleAction action,
                                        GLib.Variant?     parameter)
        {
            this.timer.start ();
        }

        private void on_stop_activate (GLib.SimpleAction action,
                                       GLib.Variant?     parameter)
        {
            this.timer.stop ();
        }

        private void on_pause_activate (GLib.SimpleAction action,
                                        GLib.Variant?     parameter)
        {
            this.timer.pause ();
        }

        private void on_resume_activate (GLib.SimpleAction action,
                                         GLib.Variant?     parameter)
        {
            this.timer.resume ();
        }
    }
}
