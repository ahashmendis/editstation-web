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
        Args: {
          extensions?: Json;
          operationName?: string;
          query?: string;
          variables?: Json;
        };
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
          details: Json;
          entity_id: string;
          entity_type: string;
          id: number;
        };
        Insert: {
          action: string;
          actor_id?: string | null;
          created_at?: string;
          details?: Json;
          entity_id: string;
          entity_type: string;
          id?: never;
        };
        Update: {
          action?: string;
          actor_id?: string | null;
          created_at?: string;
          details?: Json;
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
        Insert: {
          budget_currency?: string;
          budget_label: string;
          budget_range_id?: string | null;
          client_notes?: string | null;
          company?: string | null;
          contact_name: string;
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
      editor_portfolio_links: {
        Row: {
          created_at: string;
          editor_id: string;
          id: string;
          label: string | null;
          url: string;
        };
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
      profile_options: {
        Row: {
          active: boolean;
          code: string;
          kind: Database["public"]["Enums"]["profile_option_kind"];
          label: string;
          sort_order: number;
        };
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
      service_types: {
        Row: {
          active: boolean;
          code: string;
          created_at: string;
          label: string;
          sort_order: number;
          updated_at: string;
        };
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
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      admin_approve_application: {
        Args: {
          p_application_id: string;
          p_level: Database["public"]["Enums"]["editor_level"];
          p_message?: string;
        };
        Returns: undefined;
      };
      admin_create_application_request: {
        Args: {
          p_application_id: string;
          p_kind: Database["public"]["Enums"]["application_request_kind"];
          p_message: string;
        };
        Returns: string;
      };
      admin_record_assessment_result: {
        Args: {
          p_notes?: string;
          p_request_id: string;
          p_result: Database["public"]["Enums"]["assessment_result"];
        };
        Returns: undefined;
      };
      admin_reject_application: {
        Args: { p_application_id: string; p_message?: string };
        Returns: undefined;
      };
      admin_reopen_application: {
        Args: { p_editor_id: string };
        Returns: string;
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
      admin_start_application_review: {
        Args: { p_application_id: string };
        Returns: undefined;
      };
      respond_to_application_request: {
        Args: {
          p_request_id: string;
          p_response: string;
          p_response_link?: string;
        };
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
      withdraw_editor_application: { Args: never; Returns: string };
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
      profile_option_kind: "specialisation" | "software";
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
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
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
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
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
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
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
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
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
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
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
      profile_option_kind: ["specialisation", "software"],
    },
  },
} as const;
