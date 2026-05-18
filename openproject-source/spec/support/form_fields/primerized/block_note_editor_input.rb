# frozen_string_literal: true

module FormFields
  module Primerized
    class BlockNoteEditorInput
      include Capybara::DSL

      def open_command_dialog
        send_keys_to_editor("/")
      end

      def open_add_image_dialog
        send_keys_to_editor("/image")
        send_keys(:enter)
      end

      def open_add_work_package_dialog
        send_keys_to_editor("/work package")
        send_keys(:enter)
      end

      def fill_in(content)
        send_keys_to_editor(content)
      end

      def attach_file(path)
        input = shadow_root.find("input[type='file']", visible: false)
        input.attach_file(path, make_visible: true)
      end

      def search_work_package(text)
        page.execute_script(fill_in_work_package_search_input(text))
      end

      def search_and_select_work_package(search_term, subject)
        # These two actions have to be done together in one execution,
        # because otherwise the onBlur of the search input triggers and
        # removes the whole search input from the DOM
        page.evaluate_async_script(<<~JS)
          #{fill_in_work_package_search_input(search_term)}
          #{select_from_work_package_dropdown(subject)}
        JS
      end
      def content
        # capybara does not yet support getting content directly
        # on shadow roots
        page.evaluate_script(<<~JS)
          document.querySelector('op-block-note')
            .shadowRoot
            .innerHTML;
        JS
      end

      def shadow_root
        page.find("op-block-note").shadow_root
      end

      # Simulates pasting one or more links into the editor — a common user
      # interaction (e.g. copying a link from an email or browser and pasting it).
      #
      # Uses a synthetic ClipboardEvent because the Ctrl+K link insertion requires
      # the formatting toolbar to be visible (text must be selected first), which
      # has no reliable programmatic equivalent in Capybara/Selenium. The synthetic
      # event exercises the same ProseMirror paste handler code path as a real Ctrl+V.
      #
      # @example Single link
      #   editor.paste_links(text: "Example", url: "https://example.com")
      #
      # @example Multiple links
      #   editor.paste_links(
      #     { text: "One", url: "https://one.com" },
      #     { text: "Two", url: "https://two.com" }
      #   )
      def paste_links(*links)
        el = element
        el.click

        html = links.map { |l| %(<a href="#{l[:url]}">#{l[:text]}</a>) }.join(" ")
        plain = links.pluck(:text).join(" ")

        page.execute_script(<<~JS, el.native, html, plain)
          const el = arguments[0];
          const dt = new DataTransfer();
          dt.setData('text/html', arguments[1]);
          dt.setData('text/plain', arguments[2]);
          el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
        JS
      end

      def element
        shadow_root.find("div[role='textbox']")
      end

      private

      # Attention: This only works with selenium, not with cuprite,
      # as cuprite does not support shadow dom (yet).
      def send_keys_to_editor(keys)
        element.send_keys(keys)
      end

      def shadow_root_observe_js
        <<~JS
          function shadowRootWaitFor(shadowRoot, tryFunction, done) {
            if (tryFunction()) {
              if (done) done();
              return;
            }
            var observer = new MutationObserver(function() {
              if (tryFunction()) {
                observer.disconnect();
                if (done) done();
              }
            });
            observer.observe(shadowRoot, { childList: true, subtree: true });
          }
        JS
      end

      # Unfortunately, the search input is removed on every blur event (starting with op-blocknote-extensions 0.0.24).
      # Capybara triggers those and therefore leads to always red tests.
      # The input needs to be operated completely by javascript to avoid any blurring.
      def fill_in_work_package_search_input(text)
        <<~JS
          (function() {
            var value = #{text.to_json};
            var shadowRoot = #{shadow_root_query};
            #{shadow_root_observe_js}

            // One does not simply call `.value=` on a react input element
            shadowRootWaitFor(shadowRoot, function() {
              var input = shadowRoot.querySelector("input[placeholder='Search by work package ID or subject']");
              if (!input) return false;
              var valueSetter = Object.getOwnPropertyDescriptor(input, 'value').set;
              var prototype = Object.getPrototypeOf(input);
              var prototypeValueSetter = Object.getOwnPropertyDescriptor(prototype, 'value').set;
              prototypeValueSetter.call(input, value);
              input.dispatchEvent(new Event('change', { bubbles: true }));
              return true;
            });
          })();
        JS
      end

      # Unfortunately, the search input is removed on every blur event (starting with op-blocknote-extensions 0.0.24).
      # Capybara triggers those and therefore leads to always red tests.
      # The input needs to be operated completely by javascript to avoid any blurring.
      def select_from_work_package_dropdown(text)
        <<~JS
          (function(done) {
            var shadowRoot = #{shadow_root_query};
            var textToClick = #{text.to_json}.trim();
            #{shadow_root_observe_js}

            shadowRootWaitFor(shadowRoot, function() {
              var element = Array.prototype.slice.call(shadowRoot.querySelectorAll("div"))
                .find(function(div) { return div.textContent.trim() === textToClick; });
              if (element) {
                element.dispatchEvent(new Event("mousedown", { bubbles: true }));
                return true;
              }
              return false;
            }, done);
          })(arguments[arguments.length - 1]);
        JS
      end

      def shadow_root_query
        "document.querySelector('op-block-note').shadowRoot;"
      end
    end
  end
end
