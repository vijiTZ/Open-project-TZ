import { skip } from 'rxjs/operators';
import { fromEvent } from 'rxjs';
import { runBootstrap } from 'core-app/app.module';
import { OpenProjectPluginContext } from 'core-app/features/plugins/plugin-context';

export function addTurboAngularWrapper() {
  // When turbo:load fires, the angular application needs to be rebootstrapped.
  // However, we don't want this to happen on the initial page load
  fromEvent(document, 'turbo:load')
    .pipe(
      skip(1), // Skip the first turbo:load event
    )
    .subscribe(() => {
      void window
        .OpenProject
        .getPluginContext()
        .then((pluginContext:OpenProjectPluginContext) => {
          const appRef = pluginContext.appRef;

          // Remove all previous references to components
          // This is mainly the base component
          appRef.components.slice().forEach((component) => {
            appRef.detachView(component.hostView);
            component.destroy();
          });

          // Run bootstrap again to initialize the new application
          runBootstrap(appRef);
        });
    });
}
