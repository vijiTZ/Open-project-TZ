import { TestBed } from '@angular/core/testing';
import { EditFormComponent } from 'core-app/shared/components/fields/edit/edit-form/edit-form.component';
import { GlobalEditFormChangesTrackerService } from './global-edit-form-changes-tracker.service';

describe('GlobalEditFormChangesTrackerService', () => {
  let service:GlobalEditFormChangesTrackerService;
  const createForm = (changed?:boolean) => ({
    change: {
      isEmpty: () => !changed,
    },
  } as EditFormComponent);

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(GlobalEditFormChangesTrackerService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  it('should report no changes when empty', () => {
    expect(service.thereAreFormsWithUnsavedChanges).toBe(false);
  });

  it('should report no changes when one form has no changes', () => {
    const form = createForm();

    service.addToActiveForms(form);

    expect(service.thereAreFormsWithUnsavedChanges).toBe(false);
  });

  it('should report no changes when multiple forms have no changes', () => {
    const form = createForm();
    const form2 = createForm();
    const form3 = createForm();

    service.addToActiveForms(form);
    service.addToActiveForms(form2);
    service.addToActiveForms(form3);

    expect(service.thereAreFormsWithUnsavedChanges).toBe(false);
  });

  it('should report no changes when the only form with changes is removed', () => {
    const form = createForm(true);

    service.addToActiveForms(form);
    service.removeFromActiveForms(form);

    expect(service.thereAreFormsWithUnsavedChanges).toBe(false);
  });

  it('should report changes when one form has changes', () => {
    const form = createForm(true);

    service.addToActiveForms(form);

    expect(service.thereAreFormsWithUnsavedChanges).toBe(true);
  });

  it('should report forms with changes when multiple form have changes', () => {
    const form = createForm(true);
    const form2 = createForm(true);
    const form3 = createForm();

    service.addToActiveForms(form);
    service.addToActiveForms(form2);
    service.addToActiveForms(form3);

    expect(service.thereAreFormsWithUnsavedChanges).toBe(true);
  });

  it('should call thereAreFormsWithUnsavedChangesSpy on beforeunload', () => {
    const thereAreFormsWithUnsavedChangesSpy = vi.spyOn(service, 'thereAreFormsWithUnsavedChanges', 'get');

    window.onbeforeunload = vi.fn();

    window.dispatchEvent(new Event('beforeunload'));

    expect(thereAreFormsWithUnsavedChangesSpy).toHaveBeenCalled();
  });
});
