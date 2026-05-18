import { Controller } from '@hotwired/stimulus';
import { MainMenuToggleService } from 'core-app/core/main-menu/main-menu-toggle.service';

export default class MainToggleController extends Controller {
  mainMenuService:MainMenuToggleService|undefined;

  connect() {
    window.OpenProject.getPluginContext()
      .then((pluginContext) => pluginContext.injector.get(MainMenuToggleService))
      .then((service) => {
        if (!this.element.isConnected) return;
        this.mainMenuService = service;
        this.mainMenuService.initializeMenu();
      })
      .catch(() => { /* Do nothing */ });
  }

  disconnect() {
    this.mainMenuService = undefined;
  }

  toggleNavigation(e:Event) {
    this.mainMenuService?.toggleNavigation(e);
  }
}
