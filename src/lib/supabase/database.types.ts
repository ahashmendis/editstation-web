export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never;
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      graphql: {
        Args: { extensions?: Json; operationName?: string; query?: string; variables?: Json };
        Returns: Json;
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  public: {
    Tables: {
      activity_logs: {
        Row: {
          action: string;
          actor_id: string | null;
          created_at: string;
          details: NonNullable<Json>;
          entity_id: string;
          entity_type: string;
          id: number;
        };
        ComputedFields: never;
        Insert: {
          action: string;
          actor_id?: string | null;
          created_at?: string;
          details?: NonNullable<Json>;
          entity_id: string;
          entity_type: string;
          id?: never;
        };
        Update: {
          action?: string;
          actor_id?: string | null;
          created_at?: string;
          details?: NonNullable<Json>;
          entity_id?: string;
          entity_type?: string;
          id?: never;
        };
        Relationships: [
          {
            foreignKeyName: "activity_logs_actor_id_fkey";
            columns: ["actor_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      admin_users: {
        Row: {
          granted_at: string;
          granted_by: string | null;
          note: string | null;
          revoked_at: string | null;
          revoked_by: string | null;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          granted_at?: string;
          granted_by?: string | null;
          note?: string | null;
          revoked_at?: string | null;
          revoked_by?: string | null;
          user_id: string;
        };
        Update: {
          granted_at?: string;
          granted_by?: string | null;
          note?: string | null;
          revoked_at?: string | null;
          revoked_by?: string | null;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "admin_users_granted_by_fkey";
            columns: ["granted_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "admin_users_revoked_by_fkey";
            columns: ["revoked_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "admin_users_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: true;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      application_requests: {
        Row: {
          application_id: string;
          assessed_at: string | null;
          assessed_by: string | null;
          assessment_notes: string | null;
          assessment_result: Database["public"]["Enums"]["assessment_result"] | null;
          id: string;
          kind: Database["public"]["Enums"]["application_request_kind"];
          message: string;
          requested_at: string;
          requested_by: string | null;
          responded_at: string | null;
          response: string | null;
          response_link: string | null;
        };
        ComputedFields: never;
        Insert: {
          application_id: string;
          assessed_at?: string | null;
          assessed_by?: string | null;
          assessment_notes?: string | null;
          assessment_result?: Database["public"]["Enums"]["assessment_result"] | null;
          id?: string;
          kind: Database["public"]["Enums"]["application_request_kind"];
          message: string;
          requested_at?: string;
          requested_by?: string | null;
          responded_at?: string | null;
          response?: string | null;
          response_link?: string | null;
        };
        Update: {
          application_id?: string;
          assessed_at?: string | null;
          assessed_by?: string | null;
          assessment_notes?: string | null;
          assessment_result?: Database["public"]["Enums"]["assessment_result"] | null;
          id?: string;
          kind?: Database["public"]["Enums"]["application_request_kind"];
          message?: string;
          requested_at?: string;
          requested_by?: string | null;
          responded_at?: string | null;
          response?: string | null;
          response_link?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "application_requests_application_id_fkey";
            columns: ["application_id"];
            isOneToOne: false;
            referencedRelation: "editor_applications";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "application_requests_assessed_by_fkey";
            columns: ["assessed_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "application_requests_requested_by_fkey";
            columns: ["requested_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      asset_access_grants: {
        Row: {
          access_type: Database["public"]["Enums"]["asset_access_type"];
          created_at: string;
          editor_id: string;
          folder_url: string | null;
          id: string;
          project_id: string;
          provider: Database["public"]["Enums"]["asset_provider"];
          removal_confirmed_at: string | null;
          removal_confirmed_by: string | null;
          removal_requested_at: string | null;
          removal_requested_by: string | null;
          revoke_reason: string | null;
          revoked_at: string | null;
          revoked_by: string | null;
          shared_at: string;
          shared_by: string | null;
          shared_with_email: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          access_type?: Database["public"]["Enums"]["asset_access_type"];
          created_at?: string;
          editor_id: string;
          folder_url?: string | null;
          id?: string;
          project_id: string;
          provider: Database["public"]["Enums"]["asset_provider"];
          removal_confirmed_at?: string | null;
          removal_confirmed_by?: string | null;
          removal_requested_at?: string | null;
          removal_requested_by?: string | null;
          revoke_reason?: string | null;
          revoked_at?: string | null;
          revoked_by?: string | null;
          shared_at?: string;
          shared_by?: string | null;
          shared_with_email: string;
          updated_at?: string;
        };
        Update: {
          access_type?: Database["public"]["Enums"]["asset_access_type"];
          created_at?: string;
          editor_id?: string;
          folder_url?: string | null;
          id?: string;
          project_id?: string;
          provider?: Database["public"]["Enums"]["asset_provider"];
          removal_confirmed_at?: string | null;
          removal_confirmed_by?: string | null;
          removal_requested_at?: string | null;
          removal_requested_by?: string | null;
          revoke_reason?: string | null;
          revoked_at?: string | null;
          revoked_by?: string | null;
          shared_at?: string;
          shared_by?: string | null;
          shared_with_email?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "asset_access_grants_editor_id_fkey";
            columns: ["editor_id"];
            isOneToOne: false;
            referencedRelation: "editor_profiles";
            referencedColumns: ["user_id"];
          },
          {
            foreignKeyName: "asset_access_grants_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "asset_access_grants_removal_confirmed_by_fkey";
            columns: ["removal_confirmed_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "asset_access_grants_removal_requested_by_fkey";
            columns: ["removal_requested_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "asset_access_grants_revoked_by_fkey";
            columns: ["revoked_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "asset_access_grants_shared_by_fkey";
            columns: ["shared_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      asset_access_reports: {
        Row: {
          asset_id: string | null;
          created_at: string;
          editor_id: string;
          id: string;
          note: string;
          project_id: string;
          resolved_at: string | null;
          resolved_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          asset_id?: string | null;
          created_at?: string;
          editor_id: string;
          id?: string;
          note: string;
          project_id: string;
          resolved_at?: string | null;
          resolved_by?: string | null;
        };
        Update: {
          asset_id?: string | null;
          created_at?: string;
          editor_id?: string;
          id?: string;
          note?: string;
          project_id?: string;
          resolved_at?: string | null;
          resolved_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "asset_access_reports_asset_id_fkey";
            columns: ["asset_id"];
            isOneToOne: false;
            referencedRelation: "project_assets";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "asset_access_reports_editor_id_fkey";
            columns: ["editor_id"];
            isOneToOne: false;
            referencedRelation: "editor_profiles";
            referencedColumns: ["user_id"];
          },
          {
            foreignKeyName: "asset_access_reports_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "asset_access_reports_resolved_by_fkey";
            columns: ["resolved_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      assignments: {
        Row: {
          agreed_amount: number | null;
          agreed_currency: string | null;
          closed_at: string | null;
          confirmed_at: string | null;
          confirmed_by: string | null;
          created_at: string;
          currency: string;
          editor_id: string;
          id: string;
          project_id: string;
          proposed_amount: number;
          started_at: string | null;
          started_by: string | null;
          status: Database["public"]["Enums"]["assignment_status"];
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          agreed_amount?: number | null;
          agreed_currency?: string | null;
          closed_at?: string | null;
          confirmed_at?: string | null;
          confirmed_by?: string | null;
          created_at?: string;
          currency?: string;
          editor_id: string;
          id?: string;
          project_id: string;
          proposed_amount: number;
          started_at?: string | null;
          started_by?: string | null;
          status?: Database["public"]["Enums"]["assignment_status"];
          updated_at?: string;
        };
        Update: {
          agreed_amount?: number | null;
          agreed_currency?: string | null;
          closed_at?: string | null;
          confirmed_at?: string | null;
          confirmed_by?: string | null;
          created_at?: string;
          currency?: string;
          editor_id?: string;
          id?: string;
          project_id?: string;
          proposed_amount?: number;
          started_at?: string | null;
          started_by?: string | null;
          status?: Database["public"]["Enums"]["assignment_status"];
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "assignments_confirmed_by_fkey";
            columns: ["confirmed_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "assignments_editor_id_fkey";
            columns: ["editor_id"];
            isOneToOne: false;
            referencedRelation: "editor_profiles";
            referencedColumns: ["user_id"];
          },
          {
            foreignKeyName: "assignments_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "assignments_started_by_fkey";
            columns: ["started_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      brief_confirmations: {
        Row: {
          assignment_id: string;
          brief_version: number;
          brief_version_id: string;
          carried_from_id: string | null;
          confirmed_amount: number;
          confirmed_at: string;
          confirmed_currency: string;
          confirmed_deadline: string;
          confirmed_deliverables: NonNullable<Json>;
          created_by: string | null;
          editor_id: string;
          id: string;
          kind: Database["public"]["Enums"]["brief_confirmation_kind"];
          project_id: string;
        };
        ComputedFields: never;
        Insert: {
          assignment_id: string;
          brief_version: number;
          brief_version_id: string;
          carried_from_id?: string | null;
          confirmed_amount: number;
          confirmed_at?: string;
          confirmed_currency: string;
          confirmed_deadline: string;
          confirmed_deliverables: NonNullable<Json>;
          created_by?: string | null;
          editor_id: string;
          id?: string;
          kind: Database["public"]["Enums"]["brief_confirmation_kind"];
          project_id: string;
        };
        Update: {
          assignment_id?: string;
          brief_version?: number;
          brief_version_id?: string;
          carried_from_id?: string | null;
          confirmed_amount?: number;
          confirmed_at?: string;
          confirmed_currency?: string;
          confirmed_deadline?: string;
          confirmed_deliverables?: NonNullable<Json>;
          created_by?: string | null;
          editor_id?: string;
          id?: string;
          kind?: Database["public"]["Enums"]["brief_confirmation_kind"];
          project_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "brief_confirmations_assignment_id_fkey";
            columns: ["assignment_id"];
            isOneToOne: false;
            referencedRelation: "assignments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "brief_confirmations_brief_version_id_fkey";
            columns: ["brief_version_id"];
            isOneToOne: false;
            referencedRelation: "brief_versions";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "brief_confirmations_carried_from_id_fkey";
            columns: ["carried_from_id"];
            isOneToOne: false;
            referencedRelation: "brief_confirmations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "brief_confirmations_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "brief_confirmations_editor_id_fkey";
            columns: ["editor_id"];
            isOneToOne: false;
            referencedRelation: "editor_profiles";
            referencedColumns: ["user_id"];
          },
          {
            foreignKeyName: "brief_confirmations_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      brief_versions: {
        Row: {
          audience: string | null;
          brand_constraints: string | null;
          change_summary: string | null;
          core_message: string | null;
          created_at: string;
          created_by: string | null;
          deliverables: NonNullable<Json>;
          desired_outcome: string | null;
          id: string;
          instructions: string | null;
          mandatory_content: string | null;
          prohibited_content: string | null;
          project_id: string;
          references: NonNullable<Json>;
          requires_reacknowledgement: boolean;
          updated_at: string;
          version: number;
        };
        ComputedFields: never;
        Insert: {
          audience?: string | null;
          brand_constraints?: string | null;
          change_summary?: string | null;
          core_message?: string | null;
          created_at?: string;
          created_by?: string | null;
          deliverables?: NonNullable<Json>;
          desired_outcome?: string | null;
          id?: string;
          instructions?: string | null;
          mandatory_content?: string | null;
          prohibited_content?: string | null;
          project_id: string;
          references?: NonNullable<Json>;
          requires_reacknowledgement?: boolean;
          updated_at?: string;
          version: number;
        };
        Update: {
          audience?: string | null;
          brand_constraints?: string | null;
          change_summary?: string | null;
          core_message?: string | null;
          created_at?: string;
          created_by?: string | null;
          deliverables?: NonNullable<Json>;
          desired_outcome?: string | null;
          id?: string;
          instructions?: string | null;
          mandatory_content?: string | null;
          prohibited_content?: string | null;
          project_id?: string;
          references?: NonNullable<Json>;
          requires_reacknowledgement?: boolean;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "brief_versions_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "brief_versions_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      budget_ranges: {
        Row: {
          active: boolean;
          created_at: string;
          currency: string;
          id: string;
          label: string;
          max_amount: number | null;
          min_amount: number | null;
          sort_order: number;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          active?: boolean;
          created_at?: string;
          currency?: string;
          id?: string;
          label: string;
          max_amount?: number | null;
          min_amount?: number | null;
          sort_order?: number;
          updated_at?: string;
        };
        Update: {
          active?: boolean;
          created_at?: string;
          currency?: string;
          id?: string;
          label?: string;
          max_amount?: number | null;
          min_amount?: number | null;
          sort_order?: number;
          updated_at?: string;
        };
        Relationships: [];
      };
      client_inquiries: {
        Row: {
          budget_currency: string;
          budget_label: string;
          budget_range_id: string | null;
          client_notes: string | null;
          company: string | null;
          contact_name: string;
          converted_project_id: string | null;
          description: string;
          email: string;
          expected_deadline: string | null;
          expected_deliverables: string | null;
          id: string;
          phone: string | null;
          privacy_notice_version: string;
          service_type_code: string;
          service_type_label: string;
          status: Database["public"]["Enums"]["inquiry_status"];
          status_changed_at: string | null;
          status_changed_by: string | null;
          submitted_at: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          budget_currency?: string;
          budget_label: string;
          budget_range_id?: string | null;
          client_notes?: string | null;
          company?: string | null;
          contact_name: string;
          converted_project_id?: string | null;
          description: string;
          email: string;
          expected_deadline?: string | null;
          expected_deliverables?: string | null;
          id?: string;
          phone?: string | null;
          privacy_notice_version: string;
          service_type_code: string;
          service_type_label: string;
          status?: Database["public"]["Enums"]["inquiry_status"];
          status_changed_at?: string | null;
          status_changed_by?: string | null;
          submitted_at?: string;
          updated_at?: string;
        };
        Update: {
          budget_currency?: string;
          budget_label?: string;
          budget_range_id?: string | null;
          client_notes?: string | null;
          company?: string | null;
          contact_name?: string;
          converted_project_id?: string | null;
          description?: string;
          email?: string;
          expected_deadline?: string | null;
          expected_deliverables?: string | null;
          id?: string;
          phone?: string | null;
          privacy_notice_version?: string;
          service_type_code?: string;
          service_type_label?: string;
          status?: Database["public"]["Enums"]["inquiry_status"];
          status_changed_at?: string | null;
          status_changed_by?: string | null;
          submitted_at?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "client_inquiries_budget_range_id_fkey";
            columns: ["budget_range_id"];
            isOneToOne: false;
            referencedRelation: "budget_ranges";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "client_inquiries_converted_project_id_fkey";
            columns: ["converted_project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "client_inquiries_service_type_code_fkey";
            columns: ["service_type_code"];
            isOneToOne: false;
            referencedRelation: "service_types";
            referencedColumns: ["code"];
          },
          {
            foreignKeyName: "client_inquiries_status_changed_by_fkey";
            columns: ["status_changed_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      client_inquiry_links: {
        Row: {
          id: string;
          inquiry_id: string;
          label: string | null;
          url: string;
        };
        ComputedFields: never;
        Insert: {
          id?: string;
          inquiry_id: string;
          label?: string | null;
          url: string;
        };
        Update: {
          id?: string;
          inquiry_id?: string;
          label?: string | null;
          url?: string;
        };
        Relationships: [
          {
            foreignKeyName: "client_inquiry_links_inquiry_id_fkey";
            columns: ["inquiry_id"];
            isOneToOne: false;
            referencedRelation: "client_inquiries";
            referencedColumns: ["id"];
          },
        ];
      };
      clients: {
        Row: {
          archived_at: string | null;
          company: string | null;
          created_at: string;
          created_by: string | null;
          email: string;
          id: string;
          merged_into_id: string | null;
          name: string;
          notes: string | null;
          phone: string | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          archived_at?: string | null;
          company?: string | null;
          created_at?: string;
          created_by?: string | null;
          email: string;
          id?: string;
          merged_into_id?: string | null;
          name: string;
          notes?: string | null;
          phone?: string | null;
          updated_at?: string;
        };
        Update: {
          archived_at?: string | null;
          company?: string | null;
          created_at?: string;
          created_by?: string | null;
          email?: string;
          id?: string;
          merged_into_id?: string | null;
          name?: string;
          notes?: string | null;
          phone?: string | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "clients_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "clients_merged_into_id_fkey";
            columns: ["merged_into_id"];
            isOneToOne: false;
            referencedRelation: "clients";
            referencedColumns: ["id"];
          },
        ];
      };
      editor_applications: {
        Row: {
          attempt: number;
          created_at: string;
          decided_at: string | null;
          decided_by: string | null;
          decision_message: string | null;
          editor_id: string;
          id: string;
          privacy_version: string | null;
          reopened_by: string | null;
          reopened_from: string | null;
          review_started_at: string | null;
          review_started_by: string | null;
          status: Database["public"]["Enums"]["application_status"];
          submitted_at: string | null;
          submitted_snapshot: Json | null;
          terms_version: string | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          attempt?: number;
          created_at?: string;
          decided_at?: string | null;
          decided_by?: string | null;
          decision_message?: string | null;
          editor_id: string;
          id?: string;
          privacy_version?: string | null;
          reopened_by?: string | null;
          reopened_from?: string | null;
          review_started_at?: string | null;
          review_started_by?: string | null;
          status?: Database["public"]["Enums"]["application_status"];
          submitted_at?: string | null;
          submitted_snapshot?: Json | null;
          terms_version?: string | null;
          updated_at?: string;
        };
        Update: {
          attempt?: number;
          created_at?: string;
          decided_at?: string | null;
          decided_by?: string | null;
          decision_message?: string | null;
          editor_id?: string;
          id?: string;
          privacy_version?: string | null;
          reopened_by?: string | null;
          reopened_from?: string | null;
          review_started_at?: string | null;
          review_started_by?: string | null;
          status?: Database["public"]["Enums"]["application_status"];
          submitted_at?: string | null;
          submitted_snapshot?: Json | null;
          terms_version?: string | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "editor_applications_decided_by_fkey";
            columns: ["decided_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "editor_applications_editor_id_fkey";
            columns: ["editor_id"];
            isOneToOne: false;
            referencedRelation: "editor_profiles";
            referencedColumns: ["user_id"];
          },
          {
            foreignKeyName: "editor_applications_reopened_by_fkey";
            columns: ["reopened_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "editor_applications_reopened_from_fkey";
            columns: ["reopened_from"];
            isOneToOne: false;
            referencedRelation: "editor_applications";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "editor_applications_review_started_by_fkey";
            columns: ["review_started_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      editor_interpretations: {
        Row: {
          admin_feedback: string | null;
          assignment_id: string;
          brief_version_id: string;
          created_at: string;
          id: string;
          questions_limitations: string | null;
          reviewed_at: string | null;
          reviewed_by: string | null;
          status: Database["public"]["Enums"]["interpretation_status"];
          submitted_at: string;
          submitted_by: string | null;
          will_adapt: string | null;
          will_reproduce: string | null;
        };
        ComputedFields: never;
        Insert: {
          admin_feedback?: string | null;
          assignment_id: string;
          brief_version_id: string;
          created_at?: string;
          id?: string;
          questions_limitations?: string | null;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          status?: Database["public"]["Enums"]["interpretation_status"];
          submitted_at?: string;
          submitted_by?: string | null;
          will_adapt?: string | null;
          will_reproduce?: string | null;
        };
        Update: {
          admin_feedback?: string | null;
          assignment_id?: string;
          brief_version_id?: string;
          created_at?: string;
          id?: string;
          questions_limitations?: string | null;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          status?: Database["public"]["Enums"]["interpretation_status"];
          submitted_at?: string;
          submitted_by?: string | null;
          will_adapt?: string | null;
          will_reproduce?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "editor_interpretations_assignment_id_fkey";
            columns: ["assignment_id"];
            isOneToOne: false;
            referencedRelation: "assignments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "editor_interpretations_brief_version_id_fkey";
            columns: ["brief_version_id"];
            isOneToOne: false;
            referencedRelation: "brief_versions";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "editor_interpretations_reviewed_by_fkey";
            columns: ["reviewed_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "editor_interpretations_submitted_by_fkey";
            columns: ["submitted_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      editor_portfolio_links: {
        Row: {
          created_at: string;
          editor_id: string;
          id: string;
          label: string | null;
          url: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          editor_id: string;
          id?: string;
          label?: string | null;
          url: string;
        };
        Update: {
          created_at?: string;
          editor_id?: string;
          id?: string;
          label?: string | null;
          url?: string;
        };
        Relationships: [
          {
            foreignKeyName: "editor_portfolio_links_editor_id_fkey";
            columns: ["editor_id"];
            isOneToOne: false;
            referencedRelation: "editor_profiles";
            referencedColumns: ["user_id"];
          },
        ];
      };
      editor_profile_options: {
        Row: {
          code: string;
          created_at: string;
          editor_id: string;
          kind: Database["public"]["Enums"]["profile_option_kind"];
        };
        ComputedFields: never;
        Insert: {
          code: string;
          created_at?: string;
          editor_id: string;
          kind: Database["public"]["Enums"]["profile_option_kind"];
        };
        Update: {
          code?: string;
          created_at?: string;
          editor_id?: string;
          kind?: Database["public"]["Enums"]["profile_option_kind"];
        };
        Relationships: [
          {
            foreignKeyName: "editor_profile_options_editor_id_fkey";
            columns: ["editor_id"];
            isOneToOne: false;
            referencedRelation: "editor_profiles";
            referencedColumns: ["user_id"];
          },
          {
            foreignKeyName: "editor_profile_options_kind_code_fkey";
            columns: ["kind", "code"];
            isOneToOne: false;
            referencedRelation: "profile_options";
            referencedColumns: ["kind", "code"];
          },
        ];
      };
      editor_profiles: {
        Row: {
          access_change_reason: string | null;
          access_changed_at: string | null;
          access_changed_by: string | null;
          access_status: Database["public"]["Enums"]["editor_access_status"];
          availability: string | null;
          created_at: string;
          experience_summary: string | null;
          experience_years: number | null;
          hardware: string | null;
          level: Database["public"]["Enums"]["editor_level"] | null;
          region: string | null;
          software_other: string | null;
          typical_turnaround: string | null;
          updated_at: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          access_change_reason?: string | null;
          access_changed_at?: string | null;
          access_changed_by?: string | null;
          access_status?: Database["public"]["Enums"]["editor_access_status"];
          availability?: string | null;
          created_at?: string;
          experience_summary?: string | null;
          experience_years?: number | null;
          hardware?: string | null;
          level?: Database["public"]["Enums"]["editor_level"] | null;
          region?: string | null;
          software_other?: string | null;
          typical_turnaround?: string | null;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          access_change_reason?: string | null;
          access_changed_at?: string | null;
          access_changed_by?: string | null;
          access_status?: Database["public"]["Enums"]["editor_access_status"];
          availability?: string | null;
          created_at?: string;
          experience_summary?: string | null;
          experience_years?: number | null;
          hardware?: string | null;
          level?: Database["public"]["Enums"]["editor_level"] | null;
          region?: string | null;
          software_other?: string | null;
          typical_turnaround?: string | null;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "editor_profiles_access_changed_by_fkey";
            columns: ["access_changed_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "editor_profiles_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: true;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      editor_vetting_notes: {
        Row: {
          application_id: string;
          author_id: string | null;
          created_at: string;
          id: string;
          note: string;
        };
        ComputedFields: never;
        Insert: {
          application_id: string;
          author_id?: string | null;
          created_at?: string;
          id?: string;
          note: string;
        };
        Update: {
          application_id?: string;
          author_id?: string | null;
          created_at?: string;
          id?: string;
          note?: string;
        };
        Relationships: [
          {
            foreignKeyName: "editor_vetting_notes_application_id_fkey";
            columns: ["application_id"];
            isOneToOne: false;
            referencedRelation: "editor_applications";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "editor_vetting_notes_author_id_fkey";
            columns: ["author_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      inquiry_notes: {
        Row: {
          author_id: string | null;
          created_at: string;
          id: string;
          inquiry_id: string;
          note: string;
        };
        ComputedFields: never;
        Insert: {
          author_id?: string | null;
          created_at?: string;
          id?: string;
          inquiry_id: string;
          note: string;
        };
        Update: {
          author_id?: string | null;
          created_at?: string;
          id?: string;
          inquiry_id?: string;
          note?: string;
        };
        Relationships: [
          {
            foreignKeyName: "inquiry_notes_author_id_fkey";
            columns: ["author_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "inquiry_notes_inquiry_id_fkey";
            columns: ["inquiry_id"];
            isOneToOne: false;
            referencedRelation: "client_inquiries";
            referencedColumns: ["id"];
          },
        ];
      };
      negotiation_offers: {
        Row: {
          action: Database["public"]["Enums"]["negotiation_action"];
          amount: number | null;
          assignment_id: string;
          created_at: string;
          created_by: string | null;
          currency: string | null;
          from_role: Database["public"]["Enums"]["negotiation_role"];
          id: string;
          message: string | null;
        };
        ComputedFields: never;
        Insert: {
          action: Database["public"]["Enums"]["negotiation_action"];
          amount?: number | null;
          assignment_id: string;
          created_at?: string;
          created_by?: string | null;
          currency?: string | null;
          from_role: Database["public"]["Enums"]["negotiation_role"];
          id?: string;
          message?: string | null;
        };
        Update: {
          action?: Database["public"]["Enums"]["negotiation_action"];
          amount?: number | null;
          assignment_id?: string;
          created_at?: string;
          created_by?: string | null;
          currency?: string | null;
          from_role?: Database["public"]["Enums"]["negotiation_role"];
          id?: string;
          message?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "negotiation_offers_assignment_id_fkey";
            columns: ["assignment_id"];
            isOneToOne: false;
            referencedRelation: "assignments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "negotiation_offers_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      notifications: {
        Row: {
          body: string;
          created_at: string;
          entity_id: string;
          entity_type: string;
          id: string;
          kind: Database["public"]["Enums"]["notification_kind"];
          read_at: string | null;
          recipient_id: string;
          title: string;
        };
        ComputedFields: never;
        Insert: {
          body: string;
          created_at?: string;
          entity_id: string;
          entity_type: string;
          id?: string;
          kind: Database["public"]["Enums"]["notification_kind"];
          read_at?: string | null;
          recipient_id: string;
          title: string;
        };
        Update: {
          body?: string;
          created_at?: string;
          entity_id?: string;
          entity_type?: string;
          id?: string;
          kind?: Database["public"]["Enums"]["notification_kind"];
          read_at?: string | null;
          recipient_id?: string;
          title?: string;
        };
        Relationships: [
          {
            foreignKeyName: "notifications_recipient_id_fkey";
            columns: ["recipient_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      payment_notes: {
        Row: {
          author_id: string | null;
          created_at: string;
          id: string;
          note: string;
          payment_id: string;
        };
        ComputedFields: never;
        Insert: {
          author_id?: string | null;
          created_at?: string;
          id?: string;
          note: string;
          payment_id: string;
        };
        Update: {
          author_id?: string | null;
          created_at?: string;
          id?: string;
          note?: string;
          payment_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "payment_notes_author_id_fkey";
            columns: ["author_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payment_notes_payment_id_fkey";
            columns: ["payment_id"];
            isOneToOne: false;
            referencedRelation: "payments";
            referencedColumns: ["id"];
          },
        ];
      };
      payments: {
        Row: {
          amount: number;
          approved_at: string | null;
          approved_by: string | null;
          assignment_id: string;
          created_at: string;
          created_by: string | null;
          currency: string;
          due_date: string | null;
          editor_id: string;
          held_from_status: Database["public"]["Enums"]["payment_status"] | null;
          id: string;
          kind: Database["public"]["Enums"]["payment_kind"];
          marked_paid_at: string | null;
          marked_paid_by: string | null;
          on_hold_reason: string | null;
          project_id: string;
          reversal_reason: string | null;
          reverses_payment_id: string | null;
          status: Database["public"]["Enums"]["payment_status"];
          transaction_reference: string | null;
          transfer_date: string | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          amount: number;
          approved_at?: string | null;
          approved_by?: string | null;
          assignment_id: string;
          created_at?: string;
          created_by?: string | null;
          currency: string;
          due_date?: string | null;
          editor_id: string;
          held_from_status?: Database["public"]["Enums"]["payment_status"] | null;
          id?: string;
          kind?: Database["public"]["Enums"]["payment_kind"];
          marked_paid_at?: string | null;
          marked_paid_by?: string | null;
          on_hold_reason?: string | null;
          project_id: string;
          reversal_reason?: string | null;
          reverses_payment_id?: string | null;
          status?: Database["public"]["Enums"]["payment_status"];
          transaction_reference?: string | null;
          transfer_date?: string | null;
          updated_at?: string;
        };
        Update: {
          amount?: number;
          approved_at?: string | null;
          approved_by?: string | null;
          assignment_id?: string;
          created_at?: string;
          created_by?: string | null;
          currency?: string;
          due_date?: string | null;
          editor_id?: string;
          held_from_status?: Database["public"]["Enums"]["payment_status"] | null;
          id?: string;
          kind?: Database["public"]["Enums"]["payment_kind"];
          marked_paid_at?: string | null;
          marked_paid_by?: string | null;
          on_hold_reason?: string | null;
          project_id?: string;
          reversal_reason?: string | null;
          reverses_payment_id?: string | null;
          status?: Database["public"]["Enums"]["payment_status"];
          transaction_reference?: string | null;
          transfer_date?: string | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "payments_approved_by_fkey";
            columns: ["approved_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_assignment_id_fkey";
            columns: ["assignment_id"];
            isOneToOne: false;
            referencedRelation: "assignments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_editor_id_fkey";
            columns: ["editor_id"];
            isOneToOne: false;
            referencedRelation: "editor_profiles";
            referencedColumns: ["user_id"];
          },
          {
            foreignKeyName: "payments_marked_paid_by_fkey";
            columns: ["marked_paid_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_reverses_payment_id_fkey";
            columns: ["reverses_payment_id"];
            isOneToOne: false;
            referencedRelation: "payments";
            referencedColumns: ["id"];
          },
        ];
      };
      profile_options: {
        Row: {
          active: boolean;
          code: string;
          kind: Database["public"]["Enums"]["profile_option_kind"];
          label: string;
          sort_order: number;
        };
        ComputedFields: never;
        Insert: {
          active?: boolean;
          code: string;
          kind: Database["public"]["Enums"]["profile_option_kind"];
          label: string;
          sort_order?: number;
        };
        Update: {
          active?: boolean;
          code?: string;
          kind?: Database["public"]["Enums"]["profile_option_kind"];
          label?: string;
          sort_order?: number;
        };
        Relationships: [];
      };
      profiles: {
        Row: {
          created_at: string;
          email: string;
          full_name: string | null;
          id: string;
          phone: string | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          email: string;
          full_name?: string | null;
          id: string;
          phone?: string | null;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          email?: string;
          full_name?: string | null;
          id?: string;
          phone?: string | null;
          updated_at?: string;
        };
        Relationships: [];
      };
      project_access: {
        Row: {
          created_at: string;
          editor_id: string;
          granted_at: string;
          granted_by: string | null;
          id: string;
          project_id: string;
          reason: Database["public"]["Enums"]["project_access_reason"];
          revoked_at: string | null;
          revoked_by: string | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          editor_id: string;
          granted_at?: string;
          granted_by?: string | null;
          id?: string;
          project_id: string;
          reason: Database["public"]["Enums"]["project_access_reason"];
          revoked_at?: string | null;
          revoked_by?: string | null;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          editor_id?: string;
          granted_at?: string;
          granted_by?: string | null;
          id?: string;
          project_id?: string;
          reason?: Database["public"]["Enums"]["project_access_reason"];
          revoked_at?: string | null;
          revoked_by?: string | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_access_editor_id_fkey";
            columns: ["editor_id"];
            isOneToOne: false;
            referencedRelation: "editor_profiles";
            referencedColumns: ["user_id"];
          },
          {
            foreignKeyName: "project_access_granted_by_fkey";
            columns: ["granted_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_access_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_access_revoked_by_fkey";
            columns: ["revoked_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      project_assets: {
        Row: {
          access_instructions: string | null;
          access_status: Database["public"]["Enums"]["asset_access_status"];
          created_at: string;
          description: string | null;
          early_access: boolean;
          editor_confirmed_at: string | null;
          id: string;
          kind: string | null;
          label: string;
          notes: string | null;
          project_id: string;
          provider: Database["public"]["Enums"]["asset_provider"];
          sort_order: number;
          updated_at: string;
          url: string;
          verified_at: string | null;
          verified_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          access_instructions?: string | null;
          access_status?: Database["public"]["Enums"]["asset_access_status"];
          created_at?: string;
          description?: string | null;
          early_access?: boolean;
          editor_confirmed_at?: string | null;
          id?: string;
          kind?: string | null;
          label: string;
          notes?: string | null;
          project_id: string;
          provider?: Database["public"]["Enums"]["asset_provider"];
          sort_order?: number;
          updated_at?: string;
          url: string;
          verified_at?: string | null;
          verified_by?: string | null;
        };
        Update: {
          access_instructions?: string | null;
          access_status?: Database["public"]["Enums"]["asset_access_status"];
          created_at?: string;
          description?: string | null;
          early_access?: boolean;
          editor_confirmed_at?: string | null;
          id?: string;
          kind?: string | null;
          label?: string;
          notes?: string | null;
          project_id?: string;
          provider?: Database["public"]["Enums"]["asset_provider"];
          sort_order?: number;
          updated_at?: string;
          url?: string;
          verified_at?: string | null;
          verified_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "project_assets_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_assets_verified_by_fkey";
            columns: ["verified_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      project_deliverables: {
        Row: {
          aspect_ratio: string | null;
          created_at: string;
          duration_seconds: number | null;
          format: string | null;
          id: string;
          name: string;
          notes: string | null;
          project_id: string;
          resolution: string | null;
          sort_order: number;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          aspect_ratio?: string | null;
          created_at?: string;
          duration_seconds?: number | null;
          format?: string | null;
          id?: string;
          name: string;
          notes?: string | null;
          project_id: string;
          resolution?: string | null;
          sort_order?: number;
          updated_at?: string;
        };
        Update: {
          aspect_ratio?: string | null;
          created_at?: string;
          duration_seconds?: number | null;
          format?: string | null;
          id?: string;
          name?: string;
          notes?: string | null;
          project_id?: string;
          resolution?: string | null;
          sort_order?: number;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_deliverables_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_internal: {
        Row: {
          client_id: string | null;
          client_price: number | null;
          client_price_currency: string;
          created_at: string;
          internal_notes: string | null;
          project_id: string;
          source_inquiry_id: string | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          client_id?: string | null;
          client_price?: number | null;
          client_price_currency?: string;
          created_at?: string;
          internal_notes?: string | null;
          project_id: string;
          source_inquiry_id?: string | null;
          updated_at?: string;
        };
        Update: {
          client_id?: string | null;
          client_price?: number | null;
          client_price_currency?: string;
          created_at?: string;
          internal_notes?: string | null;
          project_id?: string;
          source_inquiry_id?: string | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_internal_client_id_fkey";
            columns: ["client_id"];
            isOneToOne: false;
            referencedRelation: "clients";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_internal_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: true;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_internal_source_inquiry_id_fkey";
            columns: ["source_inquiry_id"];
            isOneToOne: true;
            referencedRelation: "client_inquiries";
            referencedColumns: ["id"];
          },
        ];
      };
      project_notes: {
        Row: {
          author_id: string | null;
          created_at: string;
          id: string;
          note: string;
          project_id: string;
        };
        ComputedFields: never;
        Insert: {
          author_id?: string | null;
          created_at?: string;
          id?: string;
          note: string;
          project_id: string;
        };
        Update: {
          author_id?: string | null;
          created_at?: string;
          id?: string;
          note?: string;
          project_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_notes_author_id_fkey";
            columns: ["author_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_notes_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_references: {
        Row: {
          access_notes: string | null;
          category: string | null;
          created_at: string;
          early_access: boolean;
          end_seconds: number | null;
          id: string;
          observation_notes: string | null;
          priority: Database["public"]["Enums"]["reference_priority"];
          project_id: string;
          sort_order: number;
          start_seconds: number | null;
          title: string | null;
          updated_at: string;
          url: string;
        };
        ComputedFields: never;
        Insert: {
          access_notes?: string | null;
          category?: string | null;
          created_at?: string;
          early_access?: boolean;
          end_seconds?: number | null;
          id?: string;
          observation_notes?: string | null;
          priority?: Database["public"]["Enums"]["reference_priority"];
          project_id: string;
          sort_order?: number;
          start_seconds?: number | null;
          title?: string | null;
          updated_at?: string;
          url: string;
        };
        Update: {
          access_notes?: string | null;
          category?: string | null;
          created_at?: string;
          early_access?: boolean;
          end_seconds?: number | null;
          id?: string;
          observation_notes?: string | null;
          priority?: Database["public"]["Enums"]["reference_priority"];
          project_id?: string;
          sort_order?: number;
          start_seconds?: number | null;
          title?: string | null;
          updated_at?: string;
          url?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_references_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_terms: {
        Row: {
          agreed_at: string | null;
          agreed_by: string | null;
          balance_days: number;
          change_reason: string | null;
          charge_currency: string | null;
          created_at: string;
          created_by: string | null;
          deposit_days: number;
          editor_milestone_shares: number[];
          editor_pay_days: number;
          extra_round_charge: number | null;
          id: string;
          included_rounds: number;
          late_balance_days: number;
          project_id: string;
          status: Database["public"]["Enums"]["project_terms_status"];
          superseded_at: string | null;
          updated_at: string;
          version: number;
        };
        ComputedFields: never;
        Insert: {
          agreed_at?: string | null;
          agreed_by?: string | null;
          balance_days?: number;
          change_reason?: string | null;
          charge_currency?: string | null;
          created_at?: string;
          created_by?: string | null;
          deposit_days?: number;
          editor_milestone_shares?: number[];
          editor_pay_days?: number;
          extra_round_charge?: number | null;
          id?: string;
          included_rounds?: number;
          late_balance_days?: number;
          project_id: string;
          status?: Database["public"]["Enums"]["project_terms_status"];
          superseded_at?: string | null;
          updated_at?: string;
          version: number;
        };
        Update: {
          agreed_at?: string | null;
          agreed_by?: string | null;
          balance_days?: number;
          change_reason?: string | null;
          charge_currency?: string | null;
          created_at?: string;
          created_by?: string | null;
          deposit_days?: number;
          editor_milestone_shares?: number[];
          editor_pay_days?: number;
          extra_round_charge?: number | null;
          id?: string;
          included_rounds?: number;
          late_balance_days?: number;
          project_id?: string;
          status?: Database["public"]["Enums"]["project_terms_status"];
          superseded_at?: string | null;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "project_terms_agreed_by_fkey";
            columns: ["agreed_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_terms_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_terms_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_terms_stages: {
        Row: {
          client_charge_percent: number;
          created_at: string;
          editor_earned_percent: number;
          id: string;
          stage: Database["public"]["Enums"]["terms_stage"];
          terms_id: string;
        };
        ComputedFields: never;
        Insert: {
          client_charge_percent: number;
          created_at?: string;
          editor_earned_percent: number;
          id?: string;
          stage: Database["public"]["Enums"]["terms_stage"];
          terms_id: string;
        };
        Update: {
          client_charge_percent?: number;
          created_at?: string;
          editor_earned_percent?: number;
          id?: string;
          stage?: Database["public"]["Enums"]["terms_stage"];
          terms_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_terms_stages_terms_id_fkey";
            columns: ["terms_id"];
            isOneToOne: false;
            referencedRelation: "project_terms";
            referencedColumns: ["id"];
          },
        ];
      };
      projects: {
        Row: {
          archived_at: string | null;
          brief_type: Database["public"]["Enums"]["brief_type"];
          created_at: string;
          created_by: string | null;
          current_brief_version: number;
          deadline: string | null;
          first_opened_at: string | null;
          id: string;
          proposed_amount: number | null;
          proposed_currency: string;
          requires_interpretation: boolean;
          revision_allowance: number;
          service_type_code: string | null;
          status: Database["public"]["Enums"]["project_status"];
          status_before_hold: Database["public"]["Enums"]["project_status"] | null;
          summary: string | null;
          title: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          archived_at?: string | null;
          brief_type: Database["public"]["Enums"]["brief_type"];
          created_at?: string;
          created_by?: string | null;
          current_brief_version?: number;
          deadline?: string | null;
          first_opened_at?: string | null;
          id?: string;
          proposed_amount?: number | null;
          proposed_currency?: string;
          requires_interpretation?: boolean;
          revision_allowance?: number;
          service_type_code?: string | null;
          status?: Database["public"]["Enums"]["project_status"];
          status_before_hold?: Database["public"]["Enums"]["project_status"] | null;
          summary?: string | null;
          title: string;
          updated_at?: string;
        };
        Update: {
          archived_at?: string | null;
          brief_type?: Database["public"]["Enums"]["brief_type"];
          created_at?: string;
          created_by?: string | null;
          current_brief_version?: number;
          deadline?: string | null;
          first_opened_at?: string | null;
          id?: string;
          proposed_amount?: number | null;
          proposed_currency?: string;
          requires_interpretation?: boolean;
          revision_allowance?: number;
          service_type_code?: string | null;
          status?: Database["public"]["Enums"]["project_status"];
          status_before_hold?: Database["public"]["Enums"]["project_status"] | null;
          summary?: string | null;
          title?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "projects_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "projects_service_type_code_fkey";
            columns: ["service_type_code"];
            isOneToOne: false;
            referencedRelation: "service_types";
            referencedColumns: ["code"];
          },
        ];
      };
      revision_requests: {
        Row: {
          acknowledged_at: string | null;
          assignment_id: string;
          beyond_allowance: boolean;
          classified_at: string | null;
          classified_by: string | null;
          counts_against_allowance: boolean | null;
          created_at: string;
          created_by: string | null;
          id: string;
          project_id: string;
          reason: string;
          resolved_at: string | null;
          resubmitted_at: string | null;
          round_number: number | null;
          status: Database["public"]["Enums"]["revision_status"];
          submission_id: string;
          type: Database["public"]["Enums"]["revision_type"];
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          acknowledged_at?: string | null;
          assignment_id: string;
          beyond_allowance?: boolean;
          classified_at?: string | null;
          classified_by?: string | null;
          counts_against_allowance?: never;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          project_id: string;
          reason: string;
          resolved_at?: string | null;
          resubmitted_at?: string | null;
          round_number?: number | null;
          status?: Database["public"]["Enums"]["revision_status"];
          submission_id: string;
          type: Database["public"]["Enums"]["revision_type"];
          updated_at?: string;
        };
        Update: {
          acknowledged_at?: string | null;
          assignment_id?: string;
          beyond_allowance?: boolean;
          classified_at?: string | null;
          classified_by?: string | null;
          counts_against_allowance?: never;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          project_id?: string;
          reason?: string;
          resolved_at?: string | null;
          resubmitted_at?: string | null;
          round_number?: number | null;
          status?: Database["public"]["Enums"]["revision_status"];
          submission_id?: string;
          type?: Database["public"]["Enums"]["revision_type"];
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "revision_requests_assignment_id_fkey";
            columns: ["assignment_id"];
            isOneToOne: false;
            referencedRelation: "assignments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "revision_requests_classified_by_fkey";
            columns: ["classified_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "revision_requests_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "revision_requests_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "revision_requests_submission_id_fkey";
            columns: ["submission_id"];
            isOneToOne: false;
            referencedRelation: "submissions";
            referencedColumns: ["id"];
          },
        ];
      };
      service_types: {
        Row: {
          active: boolean;
          code: string;
          created_at: string;
          label: string;
          sort_order: number;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          active?: boolean;
          code: string;
          created_at?: string;
          label: string;
          sort_order?: number;
          updated_at?: string;
        };
        Update: {
          active?: boolean;
          code?: string;
          created_at?: string;
          label?: string;
          sort_order?: number;
          updated_at?: string;
        };
        Relationships: [];
      };
      submissions: {
        Row: {
          assignment_id: string;
          confirmed_deadline: string;
          created_at: string;
          editor_id: string;
          export_details: string | null;
          feedback: string | null;
          id: string;
          is_late: boolean;
          link: string;
          notes: string | null;
          outcome: Database["public"]["Enums"]["submission_outcome"] | null;
          project_id: string;
          reviewed_at: string | null;
          reviewed_by: string | null;
          revision_request_id: string | null;
          submitted_at: string;
          submitted_by: string | null;
          version: number;
        };
        ComputedFields: never;
        Insert: {
          assignment_id: string;
          confirmed_deadline: string;
          created_at?: string;
          editor_id: string;
          export_details?: string | null;
          feedback?: string | null;
          id?: string;
          is_late: boolean;
          link: string;
          notes?: string | null;
          outcome?: Database["public"]["Enums"]["submission_outcome"] | null;
          project_id: string;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          revision_request_id?: string | null;
          submitted_at?: string;
          submitted_by?: string | null;
          version: number;
        };
        Update: {
          assignment_id?: string;
          confirmed_deadline?: string;
          created_at?: string;
          editor_id?: string;
          export_details?: string | null;
          feedback?: string | null;
          id?: string;
          is_late?: boolean;
          link?: string;
          notes?: string | null;
          outcome?: Database["public"]["Enums"]["submission_outcome"] | null;
          project_id?: string;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          revision_request_id?: string | null;
          submitted_at?: string;
          submitted_by?: string | null;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "submissions_assignment_id_fkey";
            columns: ["assignment_id"];
            isOneToOne: false;
            referencedRelation: "assignments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "submissions_editor_id_fkey";
            columns: ["editor_id"];
            isOneToOne: false;
            referencedRelation: "editor_profiles";
            referencedColumns: ["user_id"];
          },
          {
            foreignKeyName: "submissions_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "submissions_reviewed_by_fkey";
            columns: ["reviewed_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "submissions_revision_request_fkey";
            columns: ["revision_request_id"];
            isOneToOne: false;
            referencedRelation: "revision_requests";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "submissions_submitted_by_fkey";
            columns: ["submitted_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      admin_add_payment_note: { Args: { p_note: string; p_payment_id: string }; Returns: string };
      admin_add_project_note: { Args: { p_note: string; p_project_id: string }; Returns: string };
      admin_agree_terms: {
        Args: { p_change_reason?: string; p_project_id: string; p_version: number };
        Returns: undefined;
      };
      admin_approve_application: {
        Args: {
          p_application_id: string;
          p_level: Database["public"]["Enums"]["editor_level"];
          p_message?: string;
        };
        Returns: undefined;
      };
      admin_approve_project: {
        Args: { p_feedback?: string; p_project_id: string };
        Returns: undefined;
      };
      admin_archive_project: {
        Args: { p_archive: boolean; p_project_id: string };
        Returns: undefined;
      };
      admin_classify_revision: {
        Args: { p_reason: string; p_revision_id: string; p_type: string };
        Returns: undefined;
      };
      admin_complete_project: { Args: { p_project_id: string }; Returns: undefined };
      admin_confirm_access_removal: { Args: { p_grant_id: string }; Returns: undefined };
      admin_confirm_assignment: { Args: { p_assignment_id: string }; Returns: undefined };
      admin_convert_inquiry: { Args: { p_input: Json; p_inquiry_id: string }; Returns: string };
      admin_create_application_request: {
        Args: {
          p_application_id: string;
          p_kind: Database["public"]["Enums"]["application_request_kind"];
          p_message: string;
        };
        Returns: string;
      };
      admin_create_client: { Args: { p_input: Json }; Returns: string };
      admin_create_project: { Args: { p_input: Json }; Returns: string };
      admin_dashboard_metrics: { Args: Record<PropertyKey, never>; Returns: Json };
      admin_grant_project_access: {
        Args: {
          p_editor_ids: string[];
          p_project_id: string;
          p_reason: Database["public"]["Enums"]["project_access_reason"];
        };
        Returns: number;
      };
      admin_make_offer: {
        Args: {
          p_amount: number;
          p_currency?: string;
          p_editor_id: string;
          p_message?: string;
          p_project_id: string;
        };
        Returns: string;
      };
      admin_mark_payment_paid: {
        Args: { p_payment_id: string; p_transaction_reference: string; p_transfer_date: string };
        Returns: undefined;
      };
      admin_merge_clients: { Args: { p_source: string; p_target: string }; Returns: undefined };
      admin_pending_revocations: {
        Args: Record<PropertyKey, never>;
        Returns: {
          access_type: Database["public"]["Enums"]["asset_access_type"];
          editor_id: string;
          folder_url: string;
          grant_id: string;
          project_id: string;
          provider: Database["public"]["Enums"]["asset_provider"];
          reason: string;
          removal_requested_at: string;
          shared_at: string;
          shared_with_email: string;
        }[];
      };
      admin_reassign: { Args: { p_assignment_id: string; p_message?: string }; Returns: undefined };
      admin_record_assessment_result: {
        Args: {
          p_notes?: string;
          p_request_id: string;
          p_result: Database["public"]["Enums"]["assessment_result"];
        };
        Returns: undefined;
      };
      admin_record_asset_grant: {
        Args: {
          p_access_type?: Database["public"]["Enums"]["asset_access_type"];
          p_editor_id: string;
          p_email: string;
          p_folder_url?: string;
          p_project_id: string;
          p_provider: Database["public"]["Enums"]["asset_provider"];
        };
        Returns: string;
      };
      admin_reject_application: {
        Args: { p_application_id: string; p_message?: string };
        Returns: undefined;
      };
      admin_release_payment_hold: { Args: { p_payment_id: string }; Returns: undefined };
      admin_reopen_application: { Args: { p_editor_id: string }; Returns: string };
      admin_request_access_removal: { Args: { p_grant_id: string }; Returns: undefined };
      admin_resolve_asset_report: { Args: { p_report_id: string }; Returns: undefined };
      admin_respond_counter: {
        Args: {
          p_action: string;
          p_amount?: number;
          p_assignment_id: string;
          p_currency?: string;
          p_message?: string;
        };
        Returns: undefined;
      };
      admin_reverse_payment: {
        Args: { p_payment_id: string; p_reason: string; p_reopen: boolean };
        Returns: string;
      };
      admin_review_interpretation: {
        Args: { p_decision: string; p_feedback?: string; p_interpretation_id: string };
        Returns: undefined;
      };
      admin_review_submission: {
        Args: {
          p_feedback?: string;
          p_outcome: string;
          p_reason?: string;
          p_revision_type?: string;
          p_submission_id: string;
        };
        Returns: string;
      };
      admin_revoke_asset_grant: {
        Args: { p_grant_id: string; p_reason?: string };
        Returns: undefined;
      };
      admin_revoke_project_access: {
        Args: { p_editor_id: string; p_project_id: string };
        Returns: undefined;
      };
      admin_save_assets: { Args: { p_items: Json; p_project_id: string }; Returns: undefined };
      admin_save_brief: { Args: { p_input: Json; p_project_id: string }; Returns: number };
      admin_save_terms_draft: { Args: { p_input: Json; p_project_id: string }; Returns: string };
      admin_set_asset_early_access: {
        Args: { p_asset_id: string; p_value: boolean };
        Returns: undefined;
      };
      admin_set_editor_access: {
        Args: {
          p_editor_id: string;
          p_reason: string;
          p_status: Database["public"]["Enums"]["editor_access_status"];
        };
        Returns: undefined;
      };
      admin_set_inquiry_status: {
        Args: {
          p_inquiry_id: string;
          p_note?: string;
          p_status: Database["public"]["Enums"]["inquiry_status"];
        };
        Returns: undefined;
      };
      admin_set_payment_due_date: {
        Args: { p_due_date: string; p_payment_id: string };
        Returns: undefined;
      };
      admin_set_payment_status: {
        Args: { p_payment_id: string; p_reason?: string; p_status: string };
        Returns: undefined;
      };
      admin_set_project_status: {
        Args: {
          p_note?: string;
          p_project_id: string;
          p_status: Database["public"]["Enums"]["project_status"];
        };
        Returns: undefined;
      };
      admin_set_reference_early_access: {
        Args: { p_reference_id: string; p_value: boolean };
        Returns: undefined;
      };
      admin_start_application_review: { Args: { p_application_id: string }; Returns: undefined };
      admin_start_work: { Args: { p_assignment_id: string }; Returns: undefined };
      admin_update_client: { Args: { p_client_id: string; p_input: Json }; Returns: undefined };
      admin_update_project: { Args: { p_input: Json; p_project_id: string }; Returns: undefined };
      admin_verify_asset: { Args: { p_asset_id: string }; Returns: undefined };
      admin_withdraw_offer: {
        Args: { p_assignment_id: string; p_message?: string };
        Returns: undefined;
      };
      editor_acknowledge_revision: {
        Args: { p_revision_id: string; p_start?: boolean };
        Returns: undefined;
      };
      editor_confirm_asset_access: { Args: { p_asset_id: string }; Returns: undefined };
      editor_confirm_brief: {
        Args: {
          p_amount: number;
          p_assignment_id: string;
          p_brief_version: number;
          p_currency: string;
          p_deadline: string;
        };
        Returns: string;
      };
      editor_get_terms: {
        Args: { p_project_id: string };
        Returns: {
          agreed_at: string;
          editor_kill_fee: Json;
          editor_milestone_shares: number[];
          included_rounds: number;
          version: number;
        }[];
      };
      editor_list_payments: {
        Args: Record<PropertyKey, never>;
        Returns: {
          amount: number;
          approved_at: string;
          created_at: string;
          currency: string;
          due_date: string;
          id: string;
          kind: Database["public"]["Enums"]["payment_kind"];
          marked_paid_at: string;
          on_hold_reason: string;
          project_id: string;
          project_title: string;
          reversal_reason: string;
          reverses_payment_id: string;
          status: Database["public"]["Enums"]["payment_status"];
          transaction_reference: string;
          transfer_date: string;
        }[];
      };
      editor_report_asset_inaccessible: {
        Args: { p_asset_id: string; p_note: string };
        Returns: string;
      };
      editor_respond_offer: {
        Args: {
          p_action: string;
          p_amount?: number;
          p_assignment_id: string;
          p_currency?: string;
          p_message?: string;
        };
        Returns: undefined;
      };
      editor_start_work: { Args: { p_assignment_id: string }; Returns: undefined };
      editor_submit_interpretation: {
        Args: {
          p_assignment_id: string;
          p_brief_version: number;
          p_questions?: string;
          p_will_adapt: string;
          p_will_reproduce: string;
        };
        Returns: string;
      };
      editor_submit_work: {
        Args: {
          p_assignment_id: string;
          p_export_details?: string;
          p_link: string;
          p_notes?: string;
        };
        Returns: string;
      };
      get_assignment_gate: {
        Args: { p_assignment_id: string };
        Returns: {
          amount_changed: boolean;
          brief_confirmed: boolean;
          compensation_approved: boolean;
          confirmed_brief_version: number;
          current_brief_version: number;
          deadline_changed: boolean;
          deliverables_changed: boolean;
          editor_active: boolean;
          interpretation_accepted: boolean;
          interpretation_required: boolean;
          project_active: boolean;
          reacknowledgement_required: boolean;
          ready: boolean;
        }[];
      };
      mark_all_notifications_read: { Args: Record<PropertyKey, never>; Returns: number };
      mark_notification_read: { Args: { p_id: string }; Returns: undefined };
      respond_to_application_request: {
        Args: { p_request_id: string; p_response: string; p_response_link?: string };
        Returns: undefined;
      };
      save_editor_profile: {
        Args: {
          p_availability: string;
          p_experience_summary: string;
          p_experience_years: number;
          p_full_name: string;
          p_hardware: string;
          p_links: Json;
          p_phone: string;
          p_region: string;
          p_software: string[];
          p_software_other: string;
          p_specialisations: string[];
          p_typical_turnaround: string;
        };
        Returns: undefined;
      };
      submit_client_inquiry: {
        Args: {
          p_budget_range_id: string;
          p_client_key?: string;
          p_client_notes: string;
          p_company: string;
          p_contact_name: string;
          p_description: string;
          p_email: string;
          p_expected_deadline: string;
          p_expected_deliverables: string;
          p_links: Json;
          p_phone: string;
          p_privacy_notice_version: string;
          p_service_type: string;
        };
        Returns: undefined;
      };
      submit_editor_application: {
        Args: { p_privacy_version: string; p_terms_version: string };
        Returns: string;
      };
      withdraw_editor_application: { Args: Record<PropertyKey, never>; Returns: string };
    };
    Enums: {
      application_request_kind: "info" | "test";
      application_status:
        | "draft"
        | "submitted"
        | "under_review"
        | "info_requested"
        | "test_requested"
        | "approved"
        | "rejected"
        | "withdrawn";
      assessment_result: "passed" | "failed" | "inconclusive";
      asset_access_status: "awaiting_access" | "verified" | "inaccessible";
      asset_access_type: "editor_account" | "anyone_with_link";
      asset_provider: "google_drive" | "dropbox" | "other";
      assignment_status:
        | "offered"
        | "counteroffer_pending"
        | "accepted"
        | "confirmed"
        | "in_progress"
        | "declined"
        | "withdrawn"
        | "not_selected"
        | "reassigned";
      brief_confirmation_kind: "confirmed" | "carried_forward";
      brief_type: "fully_instructed" | "reference_based" | "creative_led";
      editor_access_status: "none" | "active" | "suspended" | "revoked";
      editor_level: "junior" | "professional" | "specialist";
      inquiry_status:
        | "new"
        | "reviewing"
        | "contacted"
        | "in_discussion"
        | "converted"
        | "declined"
        | "closed"
        | "spam";
      interpretation_status: "submitted" | "accepted" | "changes_requested";
      negotiation_action: "offer" | "counter" | "accept" | "decline" | "withdraw";
      negotiation_role: "admin" | "editor";
      notification_kind:
        | "inquiry_new"
        | "application_new"
        | "applicant_response"
        | "counteroffer"
        | "submission"
        | "application_decision"
        | "application_request"
        | "invitation"
        | "assignment_confirmed"
        | "revision_requested"
        | "payment_paid"
        | "asset_inaccessible";
      payment_kind: "assignment" | "reversal";
      payment_status:
        "not_due" | "pending_approval" | "approved" | "processing" | "paid" | "on_hold";
      profile_option_kind: "specialisation" | "software";
      project_access_reason: "invited" | "available";
      project_status:
        | "draft"
        | "open"
        | "assigned"
        | "in_progress"
        | "in_review"
        | "revision_requested"
        | "approved"
        | "completed"
        | "on_hold"
        | "cancelled";
      project_terms_status: "draft" | "agreed" | "superseded";
      reference_priority: "essential" | "optional";
      revision_status:
        "requested" | "acknowledged" | "in_progress" | "resubmitted" | "approved" | "disputed";
      revision_type: "client_revision" | "editor_correction" | "scope_change";
      submission_outcome:
        "approved" | "revision_requested" | "rejected_needs_discussion" | "scope_change_required";
      terms_stage: "assigned" | "in_progress" | "in_review" | "revision_requested";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema["Enums"] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema["CompositeTypes"] | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      application_request_kind: ["info", "test"],
      application_status: [
        "draft",
        "submitted",
        "under_review",
        "info_requested",
        "test_requested",
        "approved",
        "rejected",
        "withdrawn",
      ],
      assessment_result: ["passed", "failed", "inconclusive"],
      asset_access_status: ["awaiting_access", "verified", "inaccessible"],
      asset_access_type: ["editor_account", "anyone_with_link"],
      asset_provider: ["google_drive", "dropbox", "other"],
      assignment_status: [
        "offered",
        "counteroffer_pending",
        "accepted",
        "confirmed",
        "in_progress",
        "declined",
        "withdrawn",
        "not_selected",
        "reassigned",
      ],
      brief_confirmation_kind: ["confirmed", "carried_forward"],
      brief_type: ["fully_instructed", "reference_based", "creative_led"],
      editor_access_status: ["none", "active", "suspended", "revoked"],
      editor_level: ["junior", "professional", "specialist"],
      inquiry_status: [
        "new",
        "reviewing",
        "contacted",
        "in_discussion",
        "converted",
        "declined",
        "closed",
        "spam",
      ],
      interpretation_status: ["submitted", "accepted", "changes_requested"],
      negotiation_action: ["offer", "counter", "accept", "decline", "withdraw"],
      negotiation_role: ["admin", "editor"],
      notification_kind: [
        "inquiry_new",
        "application_new",
        "applicant_response",
        "counteroffer",
        "submission",
        "application_decision",
        "application_request",
        "invitation",
        "assignment_confirmed",
        "revision_requested",
        "payment_paid",
        "asset_inaccessible",
      ],
      payment_kind: ["assignment", "reversal"],
      payment_status: ["not_due", "pending_approval", "approved", "processing", "paid", "on_hold"],
      profile_option_kind: ["specialisation", "software"],
      project_access_reason: ["invited", "available"],
      project_status: [
        "draft",
        "open",
        "assigned",
        "in_progress",
        "in_review",
        "revision_requested",
        "approved",
        "completed",
        "on_hold",
        "cancelled",
      ],
      project_terms_status: ["draft", "agreed", "superseded"],
      reference_priority: ["essential", "optional"],
      revision_status: [
        "requested",
        "acknowledged",
        "in_progress",
        "resubmitted",
        "approved",
        "disputed",
      ],
      revision_type: ["client_revision", "editor_correction", "scope_change"],
      submission_outcome: [
        "approved",
        "revision_requested",
        "rejected_needs_discussion",
        "scope_change_required",
      ],
      terms_stage: ["assigned", "in_progress", "in_review", "revision_requested"],
    },
  },
} as const;
